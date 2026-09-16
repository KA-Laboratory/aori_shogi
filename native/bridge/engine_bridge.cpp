// 煽り将棋: やねうら王を関数呼び出しで使うための薄いC API。
// std::cin / std::cout の streambuf を差し替え、USIのテキストを行キューで受け渡す。
// SPDX-License-Identifier: GPL-3.0-or-later
#include "engine_bridge.h"

#include <atomic>
#include <condition_variable>
#include <cstring>
#include <deque>
#include <iostream>
#include <mutex>
#include <streambuf>
#include <string>
#include <thread>

int main(int argc, char* argv[]);  // やねうら王の main.cpp

namespace {

// 入力側: engine_send() で積まれた文字列を、getline がブロッキングで読む。
class InputBuf : public std::streambuf {
public:
    void push_line(const std::string& line) {
        {
            std::lock_guard<std::mutex> lk(mu_);
            pending_ += line;
            pending_ += '\n';
        }
        cv_.notify_one();
    }

protected:
    int_type underflow() override {
        std::unique_lock<std::mutex> lk(mu_);
        cv_.wait(lk, [&] { return !pending_.empty(); });
        current_.swap(pending_);
        pending_.clear();
        char* b = current_.data();
        setg(b, b, b + current_.size());
        return traits_type::to_int_type(*gptr());
    }

private:
    std::mutex mu_;
    std::condition_variable cv_;
    std::string pending_;
    std::string current_;
};

// 出力側: 改行ごとに1行としてキューへ。
class OutputBuf : public std::streambuf {
public:
    bool pop_line(std::string& out) {
        std::lock_guard<std::mutex> lk(mu_);
        if (lines_.empty()) return false;
        out = std::move(lines_.front());
        lines_.pop_front();
        return true;
    }

protected:
    int_type overflow(int_type ch) override {
        if (ch == traits_type::eof()) return traits_type::not_eof(ch);
        put(static_cast<char>(ch));
        return ch;
    }

    std::streamsize xsputn(const char* s, std::streamsize n) override {
        for (std::streamsize i = 0; i < n; ++i) put(s[i]);
        return n;
    }

private:
    void put(char c) {
        std::lock_guard<std::mutex> lk(mu_);
        if (c == '\n') {
            if (!line_.empty() && line_.back() == '\r') line_.pop_back();
            lines_.push_back(std::move(line_));
            line_.clear();
        } else {
            line_.push_back(c);
        }
    }

    std::mutex mu_;
    std::string line_;
    std::deque<std::string> lines_;
};

InputBuf g_in;
OutputBuf g_out;
std::once_flag g_once;
std::atomic<bool> g_running{false};

}  // namespace

int engine_init(void) {
    std::call_once(g_once, [] {
        std::cin.rdbuf(&g_in);
        std::cout.rdbuf(&g_out);
        g_running = true;
        std::thread([] {
            static char arg0[] = "yaneuraou";
            char* argv[] = {arg0, nullptr};
            main(1, argv);
            g_running = false;
        }).detach();
    });
    return 0;
}

void engine_send(const char* usi_line) {
    if (usi_line == nullptr) return;
    g_in.push_line(usi_line);
}

int engine_poll(char* buf, int cap) {
    if (buf == nullptr || cap <= 0) return -1;
    std::string line;
    if (!g_out.pop_line(line)) return -1;
    int n = static_cast<int>(line.size());
    if (n > cap - 1) n = cap - 1;
    std::memcpy(buf, line.data(), n);
    buf[n] = '\0';
    return n;
}

int engine_is_running(void) { return g_running ? 1 : 0; }
