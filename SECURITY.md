# 安全策略 / Security Policy

> 本文档说明如何报告杏铃聊天社区版的安全漏洞。
>
> This document explains how to report security vulnerabilities in Xingling Chat Community Edition.

---

## 支持的版本 / Supported Versions

本项目目前仅维护一个版本线 / Only one version line is currently maintained:

| 版本 / Version | 支持状态 / Supported |
|---|---|
| 1.0.x | 是 / Yes |
| < 1.0 | 否 / No |

---

## 报告漏洞 / Reporting a Vulnerability

**注意：请勿在公开的 GitHub Issue 中报告安全漏洞。**
**Note: Please DO NOT report security vulnerabilities in public GitHub Issues.**

如果你发现安全漏洞，请通过 GitHub 的私密安全建议功能报告：

If you discover a security vulnerability, please report it via GitHub's private security advisory feature:

1. 进入仓库主页 / Go to the repository homepage
2. 点击 **Security** 标签 / Click the **Security** tab
3. 点击 **Report a vulnerability** / Click **Report a vulnerability**

或在 GitHub Issue 中留下联系方式，维护者会与你建立私密沟通渠道。

Or leave your contact information in a GitHub Issue, and the maintainer will establish a private communication channel with you.

---

## 响应时间 / Response Time

- **首次回复 / Initial response**：7 天内 / within 7 days
- **状态更新 / Status update**：每月一次 / monthly
- 我能力有限，可能无法立即修复所有报告，但会认真评估每一个报告。

I have limited ability and may not be able to fix all reports immediately, but will carefully evaluate every report.

---

## 报告时请包含 / What to Include in a Report

1. **漏洞描述**：发生了什么？/ Vulnerability description: What happened?
2. **复现步骤**：如何触发？/ Reproduction steps: How to trigger?
3. **影响评估**：可能造成什么后果？/ Impact assessment: What could be the consequences?
4. **建议修复方案**（如有）/ Suggested fix (if any)
5. **环境信息**：平台、Flutter 版本 / Environment info: Platform, Flutter version

---

## 安全设计说明 / Security Design Notes

本项目作为**客户端本地应用后端**，在安全方面有以下设计：

As a **client-side local application backend**, this project has the following security designs:

- **API Key 存储 / API Key storage**：通过 `flutter_secure_storage` 使用平台硬件加密（Android Keystore / iOS Keychain）
- **`.env` 文件 / `.env` file**：仅用于开发期默认配置，已在 `.gitignore` 中忽略，不应提交
- **无服务端 / No server-side**：本项目不含服务端组件，所有数据存储在用户设备本地
- **无用户认证 / No user authentication**：因无服务端，不存在用户认证场景

---

## 不属于安全漏洞的情况 / What Is NOT a Security Vulnerability

以下情况不应作为安全漏洞报告 / The following should NOT be reported as security vulnerabilities:

- 用户在 `.env` 文件中填入真实 API Key 后被自己泄露（这是用户操作问题）
- User leaking their own real API keys after filling them into `.env` (this is a user operational issue)
- 用户主动将含敏感信息的代码提交到公开仓库
- User actively committing code containing sensitive information to a public repository
- 已知依赖库的漏洞（请直接向依赖库维护者报告）
- Known vulnerabilities in dependencies (please report directly to the dependency maintainers)

---

## 致谢 / Acknowledgments

感谢每一位负责任地报告安全漏洞的研究者。

Thank you to every researcher who responsibly reports security vulnerabilities.
