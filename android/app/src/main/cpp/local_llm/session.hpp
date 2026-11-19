#pragma once
#include <atomic>
#include <functional>
#include <memory>
#include <string>
#include <vector>
#include "llm/llm.hpp"

namespace finora {
using Messages = MNN::Transformer::ChatMessages;
struct Metrics {
    int promptTokens = 0;
    int outputTokens = 0;
    double loadMs = 0;
    double firstTokenMs = -1;
    double totalMs = 0;
    double prefillMs = 0;
    double decodeMs = 0;
    std::string reason;
};
// The owner serializes every operation except requestCancel(). No object is
// destroyed or reset until generate() has returned on that same worker.
class Session {
public:
    ~Session();
    void load(const std::string& configPath);
    int tokenize(const Messages& messages);
    Metrics generate(const Messages& messages, int maxTokens, int contextTokens,
                     const std::function<void(const std::string&)>& onDelta,
                     const std::function<bool()>& shouldStop = {});
    void requestCancel() { cancelled_.store(true); }
    void prepare() { cancelled_.store(false); }
    void unload();
    bool loaded() const { return llm_ != nullptr; }
    double loadMs() const { return loadMs_; }
private:
    std::unique_ptr<MNN::Transformer::Llm> llm_;
    std::atomic<bool> cancelled_{false};
    double loadMs_ = 0;
};
}
