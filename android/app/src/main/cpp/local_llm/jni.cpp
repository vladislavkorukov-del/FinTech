#include <jni.h>
#include <string>
#include <vector>
#include <stdexcept>
#include "session.hpp"

namespace {
finora::Session session;
std::string utf8(JNIEnv* env, jstring value) {
    jclass cls = env->FindClass("java/lang/String");
    jmethodID getBytes = env->GetMethodID(cls, "getBytes", "(Ljava/lang/String;)[B");
    jstring charset = env->NewStringUTF("UTF-8");
    auto bytes = static_cast<jbyteArray>(env->CallObjectMethod(value, getBytes, charset));
    auto len = env->GetArrayLength(bytes);
    std::string result(static_cast<size_t>(len), '\0');
    env->GetByteArrayRegion(bytes, 0, len, reinterpret_cast<jbyte*>(&result[0]));
    env->DeleteLocalRef(bytes); env->DeleteLocalRef(charset); env->DeleteLocalRef(cls);
    return result;
}
jstring javaString(JNIEnv* env, const std::string& value) {
    jclass cls = env->FindClass("java/lang/String");
    auto ctor = env->GetMethodID(cls, "<init>", "([BLjava/lang/String;)V");
    auto bytes = env->NewByteArray(static_cast<jsize>(value.size()));
    env->SetByteArrayRegion(bytes, 0, static_cast<jsize>(value.size()), reinterpret_cast<const jbyte*>(value.data()));
    auto charset = env->NewStringUTF("UTF-8");
    auto result = static_cast<jstring>(env->NewObject(cls, ctor, bytes, charset));
    env->DeleteLocalRef(bytes); env->DeleteLocalRef(charset); env->DeleteLocalRef(cls);
    return result;
}
finora::Messages messages(JNIEnv* env, jobjectArray roles, jobjectArray contents) {
    auto len = env->GetArrayLength(roles);
    if (len == 0 || len != env->GetArrayLength(contents) || len > 64) throw std::runtime_error("Некорректные сообщения");
    finora::Messages result;
    for (int i = 0; i < len; ++i) {
        auto role = static_cast<jstring>(env->GetObjectArrayElement(roles, i));
        auto content = static_cast<jstring>(env->GetObjectArrayElement(contents, i));
        auto r = utf8(env, role); auto c = utf8(env, content);
        env->DeleteLocalRef(role); env->DeleteLocalRef(content);
        if (r != "system" && r != "user" && r != "assistant") throw std::runtime_error("Недопустимая роль");
        if (c.size() > 100000) throw std::runtime_error("Сообщение слишком велико");
        result.emplace_back(r, c);
    }
    return result;
}
void fail(JNIEnv* env, const std::exception& error) {
    // No prompts, responses or paths in Java/logcat error details.
    env->ThrowNew(env->FindClass("java/lang/IllegalStateException"), error.what());
}
}
extern "C" JNIEXPORT jdouble JNICALL
Java_com_finora_fintech_local_1llm_LocalLlmBridge_nativeLoad(JNIEnv* env, jobject, jstring path) {
    try { session.load(utf8(env, path)); return session.loadMs(); }
    catch (const std::exception& e) { fail(env, e); return 0; }
}
extern "C" JNIEXPORT jint JNICALL
Java_com_finora_fintech_local_1llm_LocalLlmBridge_nativeTokenize(JNIEnv* env, jobject, jobjectArray roles, jobjectArray contents) {
    try { return session.tokenize(messages(env, roles, contents)); }
    catch (const std::exception& e) { fail(env, e); return 0; }
}
extern "C" JNIEXPORT jobjectArray JNICALL
Java_com_finora_fintech_local_1llm_LocalLlmBridge_nativeGenerate(JNIEnv* env, jobject owner, jobjectArray roles, jobjectArray contents, jint maxTokens, jint contextTokens) {
    try {
        auto cls = env->GetObjectClass(owner);
        auto callback = env->GetMethodID(cls, "onNativeDelta", "([B)V");
        auto pressure = env->GetMethodID(cls, "shouldStopForPressure", "()Z");
        std::string text;
        auto result = session.generate(messages(env, roles, contents), maxTokens, contextTokens,
            [&](const std::string& delta) {
                text += delta;
                auto bytes = env->NewByteArray(static_cast<jsize>(delta.size()));
                env->SetByteArrayRegion(bytes, 0, static_cast<jsize>(delta.size()), reinterpret_cast<const jbyte*>(delta.data()));
                env->CallVoidMethod(owner, callback, bytes);
                env->DeleteLocalRef(bytes);
            }, [&]() { return env->CallBooleanMethod(owner, pressure) == JNI_TRUE; });
        std::vector<std::string> fields{text, result.reason, std::to_string(result.promptTokens), std::to_string(result.outputTokens),
            std::to_string(result.loadMs), std::to_string(result.firstTokenMs), std::to_string(result.totalMs),
            std::to_string(result.prefillMs), std::to_string(result.decodeMs)};
        auto array = env->NewObjectArray(static_cast<jsize>(fields.size()), env->FindClass("java/lang/String"), nullptr);
        for (size_t i = 0; i < fields.size(); ++i) {
            auto item = javaString(env, fields[i]); env->SetObjectArrayElement(array, static_cast<jsize>(i), item); env->DeleteLocalRef(item);
        }
        env->DeleteLocalRef(cls);
        return array;
    } catch (const std::exception& e) { fail(env, e); return nullptr; }
}
extern "C" JNIEXPORT void JNICALL
Java_com_finora_fintech_local_1llm_LocalLlmBridge_nativePrepare(JNIEnv*, jobject) { session.prepare(); }
extern "C" JNIEXPORT void JNICALL
Java_com_finora_fintech_local_1llm_LocalLlmBridge_nativeCancel(JNIEnv*, jobject) { session.requestCancel(); }
extern "C" JNIEXPORT void JNICALL
Java_com_finora_fintech_local_1llm_LocalLlmBridge_nativeUnload(JNIEnv*, jobject) { session.unload(); }
