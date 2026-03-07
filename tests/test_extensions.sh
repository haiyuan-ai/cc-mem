#!/bin/bash
# 扩展目录 smoke test

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

source "$SCRIPT_DIR/test_framework.sh"

EXT_DIR="$ROOT_DIR/extensions/opencode"

test_opencode_extension_layout() {
    describe "OpenCode 扩展目录"

    it "应该存在扩展 package.json"
    assert_file_exists "$EXT_DIR/package.json" "应该存在扩展 package.json"
    it "应该存在扩展说明文档"
    assert_file_exists "$EXT_DIR/README.md" "应该存在扩展说明文档"
    it "应该存在插件入口"
    assert_file_exists "$EXT_DIR/src/plugin.ts" "应该存在插件入口"
    it "应该存在 MCP 客户端"
    assert_file_exists "$EXT_DIR/src/mcp-client.ts" "应该存在 MCP 客户端"
    it "应该存在注入逻辑"
    assert_file_exists "$EXT_DIR/src/inject.ts" "应该存在注入逻辑"
    it "应该存在 recall 逻辑"
    assert_file_exists "$EXT_DIR/src/recall.ts" "应该存在 recall 逻辑"
    it "应该存在 capture 逻辑"
    assert_file_exists "$EXT_DIR/src/capture.ts" "应该存在 capture 逻辑"
    it "应该存在示例配置"
    assert_file_exists "$EXT_DIR/examples/opencode.config.ts" "应该存在示例配置"
}

test_opencode_extension_contract() {
    describe "OpenCode 扩展契约"

    local plugin_content package_content readme_content
    plugin_content="$(cat "$EXT_DIR/src/plugin.ts")"
    package_content="$(cat "$EXT_DIR/package.json")"
    readme_content="$(cat "$EXT_DIR/README.md")"

    it "应声明 OpenCode 插件依赖"
    assert_contains "$package_content" "@opencode-ai/plugin" "应声明 OpenCode 插件依赖"
    it "应声明 OpenCode SDK 依赖"
    assert_contains "$package_content" "@opencode-ai/sdk" "应声明 OpenCode SDK 依赖"

    it "应接入 system transform"
    assert_contains "$plugin_content" "\"experimental.chat.system.transform\"" "应接入 system transform"
    it "应接入 chat message recall"
    assert_contains "$plugin_content" "\"chat.message\"" "应接入 chat message recall"
    it "应接入 tool execute after capture"
    assert_contains "$plugin_content" "\"tool.execute.after\"" "应接入 tool execute after capture"

    it "文档应说明 inject-context 能力"
    assert_contains "$readme_content" "ccmem_inject_context" "文档应说明 inject-context 能力"
    it "文档应说明 recall 能力"
    assert_contains "$readme_content" "ccmem_recall" "文档应说明 recall 能力"
    it "文档应说明 capture 能力"
    assert_contains "$readme_content" "ccmem_capture" "文档应说明 capture 能力"
}

main() {
    run_tests "扩展 smoke test"
    test_opencode_extension_layout
    test_opencode_extension_contract
    print_summary
}

main "$@"
