#include "session.hpp"
#include <iostream>
#include <string>
#include <fstream>
#include <sstream>
#include "ujson.hpp"
int main(int argc, char** argv) {
    if (argc < 2) { std::cerr << "usage: finora_llm_probe CONFIG [PROMPT] [CANCEL_AFTER_CHUNKS] | CONFIG --messages FILE\n"; return 2; }
    try {
        finora::Session session;
        session.load(argv[1]);
        std::cout << "MODEL_LOADED load_ms=" << session.loadMs() << '\n';
        finora::Messages messages{{"system", "Ты Финора, доброжелательный помощник. Отвечай кратко на русском языке. Не показывай размышления."},
                                  {"user", argc > 2 ? argv[2] : "Привет! Как начать вести личный бюджет?"}};
        const bool fromFile = argc > 3 && std::string(argv[2]) == "--messages";
        if (fromFile) {
            std::ifstream file(argv[3]);
            if (!file) throw std::runtime_error("Messages file not found");
            std::ostringstream contents; contents << file.rdbuf();
            auto json = ujson::json::parse(contents.str());
            auto list = json.is_array() ? json : json["messages"];
            if (!list.is_array() || list.empty()) throw std::runtime_error("Expected nonempty messages array");
            messages.clear();
            for (size_t i = 0; i < list.size(); ++i) {
                messages.emplace_back(list[i]["role"].get<std::string>(), list[i]["content"].get<std::string>());
            }
        }
        std::cout << "PROMPT_TOKENS=" << session.tokenize(messages) << "\nANSWER=" << std::flush;
        int chunks = 0;
        int cancelAfter = !fromFile && argc > 3 ? std::stoi(argv[3]) : 0;
        session.prepare();
        auto metrics = session.generate(messages, 256, 2048, [&](const std::string& delta) {
            std::cout << delta << std::flush;
            if (cancelAfter && ++chunks >= cancelAfter) session.requestCancel();
        });
        std::cout << "\nRESULT=" << metrics.reason << " prompt_tokens=" << metrics.promptTokens
                  << " output_tokens=" << metrics.outputTokens << " first_token_ms=" << metrics.firstTokenMs
                  << " total_ms=" << metrics.totalMs << " prefill_ms=" << metrics.prefillMs
                  << " decode_ms=" << metrics.decodeMs << '\n';
        session.unload();
        std::cout << "MODEL_RELEASED\n";
        return 0;
    } catch (const std::exception& e) { std::cerr << "ERROR=" << e.what() << '\n'; return 1; }
}
