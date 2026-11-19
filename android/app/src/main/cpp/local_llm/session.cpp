#include "session.hpp"
#include <chrono>
#include <stdexcept>
#include <streambuf>
#include <ostream>

namespace finora {
namespace {
using Clock = std::chrono::steady_clock;
double elapsed(Clock::time_point start) {
    return std::chrono::duration<double, std::milli>(Clock::now() - start).count();
}
// The legacy 0.8B tokenizer uses recursive std::regex. An unbroken 50k-letter
// word reproduces stack overflow in libstdc++ before a token count is returned.
// Reject oversized input and pathological character-class runs BEFORE entering
// upstream code. Do not silently cut user text or structured context.
void validateTokenizerInput(const std::string& text) {
    if (text.size() > 16384) throw std::runtime_error("Сообщение слишком длинное для локальной модели");
    int previous = -1;
    size_t run = 0;
    for (const unsigned char c : text) {
        const int category = (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') ? 1 :
            c >= '0' && c <= '9' ? 2 : c == ' ' || (c >= 9 && c <= 13) ? 3 : 4;
        run = category == previous ? run + 1 : 1;
        previous = category;
        if (run > 512) throw std::runtime_error("Слишком длинная последовательность символов. Сократите сообщение");
    }
}
// MNN token strings can end inside a UTF-8 codepoint. Never send broken UTF-8
// to Flutter; keep at most three trailing bytes until the next token arrives.
class Utf8Stream : public std::streambuf {
public:
    explicit Utf8Stream(std::function<void(const std::string&)> emit) : emit_(std::move(emit)) {}
protected:
    std::streamsize xsputn(const char* chars, std::streamsize size) override {
        pending_.append(chars, static_cast<size_t>(size));
        flushComplete();
        return size;
    }
    int overflow(int c) override {
        if (c != traits_type::eof()) { pending_.push_back(static_cast<char>(c)); flushComplete(); }
        return traits_type::not_eof(c);
    }
    int sync() override { flushComplete(); return 0; }
private:
    void flushComplete() {
        size_t pos = 0;
        while (pos < pending_.size()) {
            const unsigned char lead = pending_[pos];
            size_t width = lead < 0x80 ? 1 : (lead & 0xe0) == 0xc0 ? 2 :
                           (lead & 0xf0) == 0xe0 ? 3 : (lead & 0xf8) == 0xf0 ? 4 : 1;
            if (pos + width > pending_.size()) break;
            pos += width;
        }
        if (pos) { auto text = pending_.substr(0, pos); pending_.erase(0, pos); emit_(text); }
    }
    std::function<void(const std::string&)> emit_;
    std::string pending_;
};
}
Session::~Session() { unload(); }
void Session::load(const std::string& path) {
    unload();
    auto start = Clock::now();
    std::unique_ptr<MNN::Transformer::Llm> candidate(MNN::Transformer::Llm::createLLM(path));
    if (!candidate || !candidate->load()) throw std::runtime_error("Не удалось загрузить локальную модель");
    // Explicitly disable thinking after MNN merges model metadata/config.
    if (!candidate->set_config(R"({"backend_type":"cpu","thread_num":4,"max_new_tokens":256,"timeout_ms":120000,"reuse_kv":false,"prompt_cache":false,"jinja":{"context":{"enable_thinking":false}}})"))
        throw std::runtime_error("Не удалось настроить локальную модель");
    llm_ = std::move(candidate);
    loadMs_ = elapsed(start);
}
int Session::tokenize(const Messages& messages) {
    if (!llm_) throw std::runtime_error("Модель не загружена");
    size_t bytes = 0;
    for (const auto& message : messages) {
        validateTokenizerInput(message.second);
        bytes += message.second.size();
        if (bytes > 32768) throw std::runtime_error("Контекст слишком велик для локальной модели");
    }
    const auto prompt = llm_->apply_chat_template(messages);
    if (prompt.empty()) throw std::runtime_error("Пустой шаблон запроса");
    validateTokenizerInput(prompt);
    return static_cast<int>(llm_->tokenizer_encode(prompt).size());
}
Metrics Session::generate(const Messages& messages, int maxTokens, int contextTokens,
                         const std::function<void(const std::string&)>& onDelta,
                         const std::function<bool()>& shouldStop) {
    using MNN::Transformer::LlmStatus;
    if (!llm_) throw std::runtime_error("Модель не загружена");
    if (maxTokens < 1 || maxTokens > 256 || contextTokens < 256 || contextTokens > 2048)
        throw std::runtime_error("Недопустимый размер контекста");
    Metrics result;
    result.loadMs = loadMs_;
    result.promptTokens = tokenize(messages);
    if (result.promptTokens + maxTokens > contextTokens)
        throw std::runtime_error("Запрос превышает бюджет токенов");
    const auto start = Clock::now();
    Utf8Stream stream([&](const std::string& delta) {
        if (cancelled_.load()) return;
        if (result.firstTokenMs < 0) result.firstTokenMs = elapsed(start);
        onDelta(delta);
    });
    std::ostream output(&stream);
    // Reset retains the loaded runtime, but discards stale KV after a cancelled
    // turn. The complete, explicitly budgeted chat is supplied on every turn.
    llm_->reset();
    llm_->generate_init();
    if (!cancelled_.load()) llm_->response(messages, &output, "", 0);
    auto context = llm_->getContext();
    while (!cancelled_.load() && !llm_->stoped() && context->gen_seq_len < maxTokens) {
        if (shouldStop && shouldStop()) { cancelled_.store(true); break; }
        if (elapsed(start) >= 120000) break;
        llm_->generate(1);
        if (context->status == LlmStatus::INTERNAL_ERROR || context->status == LlmStatus::TIMEOUT) break;
    }
    result.totalMs = elapsed(start);
    result.outputTokens = context->gen_seq_len;
    result.prefillMs = context->prefill_us / 1000.0;
    result.decodeMs = context->decode_us / 1000.0;
    if (cancelled_.load()) result.reason = "cancelled";
    else if (context->status == LlmStatus::TIMEOUT || result.totalMs >= 120000) result.reason = "timeout";
    else if (context->status == LlmStatus::INTERNAL_ERROR) throw std::runtime_error("Ошибка локальной генерации");
    else if (context->gen_seq_len >= maxTokens && !llm_->stoped()) result.reason = "length";
    else result.reason = "completed";
    return result;
}
void Session::unload() { llm_.reset(); }
}
