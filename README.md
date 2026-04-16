# CCodexUsageBar

一个极简 macOS 菜单栏 App：在右上角直接显示 CCodex 当天剩余额度。

## 目标系统

- macOS 12
- macOS 13
- macOS 14
- macOS 15

## 当前版本特点

- 菜单栏显示：`余 $165.73`
- 首次通过 **邮箱 / 密码** 在 App 内直接登录
- 登录成功后自动保存 `access_token` / `refresh_token`
- 后台自动刷新额度
- `401` 时自动尝试 refresh token
- 可选：把密码保存在本机钥匙串，以便 refresh 失效后自动重登
- 不再依赖外部浏览器读取 token 作为主路径

## 数据来源

- `POST /api/v1/auth/login`
- `POST /api/v1/auth/refresh`
- `GET /api/v1/usage/stats`
- `GET /api/v1/subscriptions/active`

主显示逻辑：

```text
remaining = daily_limit_usd - total_actual_cost
```

## 首次使用

### 1) 启动 App

```bash
open build/CCodexUsageBar.app
```

### 2) 在弹出的登录窗里输入

- 邮箱
- 密码

可选勾选：

- **将密码保存在本机钥匙串，以便 refresh 失效时自动重登**

### 3) 登录成功后

App 会：

- 保存 token
- 自动刷新额度
- 菜单栏显示剩余额度

## 构建

### 方案 A：直接脚本构建

```bash
cd apps/CCodexUsageBar
bash build.sh
```

输出：

```text
build/CCodexUsageBar.app
```

当前脚本会生成 **Universal 2** 二进制：

- `arm64`
- `x86_64`

因此可同时覆盖：

- Apple Silicon 的 macOS 12+
- Intel 的 macOS 12+

### 方案 B：未来装好完整 Xcode 后

本目录带有 `project.yml`，可用 XcodeGen 生成工程：

```bash
cd apps/CCodexUsageBar
xcodegen generate
```

## 运行

```bash
open build/CCodexUsageBar.app
```

## 目录结构

```text
CCodexUsageBar/
├── README.md
├── build.sh
├── project.yml
├── Resources/
│   └── Info.plist
└── Sources/
    ├── AppDelegate.swift
    ├── AuthManager.swift
    ├── BrowserTokenReader.swift
    ├── CCodexAPI.swift
    ├── KeychainTokenStore.swift
    ├── LoginWindowController.swift
    ├── Models.swift
    ├── PreferencesStore.swift
    ├── PreferencesWindowController.swift
    ├── StatusBarController.swift
    └── main.swift
```

## 说明

当前主路径已经切换为：

- **App 内原生登录**
- **自动 refresh token**
- **菜单栏常驻显示剩余额度**

`BrowserTokenReader.swift` 目前仅保留作辅助研究产物，不再是主登录方式。
