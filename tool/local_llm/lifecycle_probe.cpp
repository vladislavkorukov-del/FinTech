#include "session.hpp"
#include <condition_variable>
#include <iostream>
#include <mutex>
#include <thread>
int main(int argc, char** argv) {
    if (argc != 2) { std::cerr << "usage: lifecycle_probe CONFIG\n"; return 2; }
    try {
        finora::Session session;
        session.load(argv[1]);
        std::mutex mutex;
        std::condition_variable tokenReady;
        bool first = false;
        std::thread stopper([&] {
            std::unique_lock<std::mutex> lock(mutex);
            tokenReady.wait(lock, [&]{ return first; });
            session.requestCancel();
        });
        session.prepare();
        auto cancelled = session.generate({{"user", "Расскажи, как составить бюджет."}}, 256, 2048,
            [&](const std::string&) {
                { std::lock_guard<std::mutex> lock(mutex); first = true; }
                tokenReady.notify_one();
            });
        // In the unusual empty-response case, also release the stopper thread.
        { std::lock_guard<std::mutex> lock(mutex); first = true; }
        tokenReady.notify_one(); stopper.join();
        std::cout << "CROSS_THREAD_CANCEL=" << cancelled.reason << '\n';
        if (cancelled.reason != "cancelled") return 1;
        bool guarded = false;
        try { session.tokenize({{"user", std::string(50000, 'A')}}); }
        catch (const std::exception&) { guarded = true; }
        if (!guarded) return 1;
        std::cout << "PATHOLOGICAL_INPUT_REJECTED\n";
        bool rejected = false;
        std::string manyWords;
        for (int i = 0; i < 2500; ++i) manyWords += "hi ";
        try { session.generate({{"user", manyWords}}, 256, 2048, [](const std::string&){}); }
        catch (const std::exception&) { rejected = true; }
        if (!rejected) return 1;
        std::cout << "CONTEXT_OVERFLOW_REJECTED\n";
        session.prepare();
        auto again = session.generate({{"user", "Ответь только одним словом: готово."}}, 256, 2048,
            [](const std::string& text) { std::cout << text << std::flush; });
        std::cout << "\nREUSE_AFTER_CANCEL=" << again.reason << " tokens=" << again.outputTokens << '\n';
        session.unload();
        if (session.loaded()) return 1;
        std::cout << "RELEASED\n";
        return again.reason == "completed" ? 0 : 1;
    } catch (const std::exception& e) { std::cerr << "ERROR=" << e.what() << '\n'; return 1; }
}
