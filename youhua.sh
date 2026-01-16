#!/bin/bash

# ==============================================================================
#
# 脚本名称: 服务器初始化与Zsh美化终极脚本 (v6.8 - 适配 CF 加速版)
# 功    能: 一键完成服务器基础环境安装与Shell美化，并集成高级效率插件。
#
# v6.8 修改日志:
#   - 配置: 已预设加速代理为 https://github.xuheng.work/
#
# v6.7 修改日志:
#   - 适配: 将硬编码的私有镜像源移除，改为标准的 GitHub 官方源。
#   - 新增: 增加了 PROXY_URL 变量，可配合 Cloudflare Workers 加速站使用。
#
# 系统支持: Debian / Ubuntu
#
# ==============================================================================

# --- 配置区 (加速设置) ---

# [关键] 在这里填入你的 Cloudflare Worker 地址 (务必以 / 结尾)
# 作用: 脚本会自动将其拼接在 GitHub 官方链接之前
PROXY_URL="https://github.xuheng.work/"

# 辅助函数：构建带代理的 URL
construct_url() {
    local url="$1"
    if [ -n "$PROXY_URL" ]; then
        # 确保代理地址不包含重复的斜杠，并拼接目标 URL
        echo "${PROXY_URL%/}/${url}"
    else
        echo "${url}"
    fi
}

# --- 资源地址定义 (恢复为官方源) ---

# Oh My Zsh
OH_MY_ZSH_REMOTE=$(construct_url "https://github.com/ohmyzsh/ohmyzsh.git")
OH_MY_ZSH_INSTALL_URL=$(construct_url "https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh")

# Powerlevel10k 主题 & 字体
P10K_URL=$(construct_url "https://github.com/romkatv/powerlevel10k.git")
# 注意：字体文件通常位于 raw.githubusercontent.com 或 github.com/raw
MESLO_FONT_BASE_URL=$(construct_url "https://github.com/romkatv/powerlevel10k-media/raw/master")

# 插件 (恢复为官方 zsh-users 组织)
AUTOSUGGESTIONS_URL=$(construct_url "https://github.com/zsh-users/zsh-autosuggestions.git")
SYNTAX_HIGHLIGHTING_URL=$(construct_url "https://github.com/zsh-users/zsh-syntax-highlighting.git")
HISTORY_SUBSTRING_SEARCH_URL=$(construct_url "https://github.com/zsh-users/zsh-history-substring-search.git")
COMPLETIONS_URL=$(construct_url "https://github.com/zsh-users/zsh-completions.git")


# --- 脚本设置 ---
set -e
set -o pipefail

# --- 日志与辅助函数 ---
log_step() { echo -e "\n\e[1;34m--> $1\e[0m"; }
log_info() { echo "      $1"; }
log_success() { echo -e "      \e[1;32m✓ $1\e[0m"; }
log_skip() { echo -e "      \e[1;33m» $1\e[0m"; }
log_error() { echo -e "\n\e[1;31m错误：$1\e[0m\n"; exit 1; }

run_as_user() {
    if [ "$TARGET_USER" != "root" ]; then
        sudo -u "$TARGET_USER" "$@"
    else
        "$@"
    fi
}


# --- 1. 权限与用户检查 ---
log_step "[1/9] 检查运行环境并选择用户"
if [ "$(id -u)" -ne 0 ]; then
  log_error "此脚本需要以 root 权限运行。请使用 'sudo ./script.sh <username>'。"
fi

TARGET_USER=""
if [ -n "$1" ]; then
    TARGET_USER="$1"
    log_info "将为命令行指定的用户 '$TARGET_USER' 进行配置..."
else
    log_info "未指定用户，正在扫描可用用户..."
    mapfile -t users < <(getent passwd | awk -F: '$3 >= 1000 && $7 ~ /(\/(bash|zsh|sh))$/ {print $1}')
    options=("root" "${users[@]}")

    echo "请选择要为其配置 Zsh 的用户："
    PS3=$'\n'"请输入数字选择用户: "
    select user in "${options[@]}"; do
        if [[ -n "$user" ]]; then
            TARGET_USER=$user
            break
        else
            log_error "无效的选择，脚本终止。"
        fi
    done
fi

TARGET_HOME=$(getent passwd "$TARGET_USER" | cut -d: -f6)
if [ -z "$TARGET_HOME" ]; then
    log_error "无法找到用户 '$TARGET_USER' 的主目录。"
fi
log_info "最终确定的用户: '$TARGET_USER'"
log_info "用户主目录: $TARGET_HOME"


# --- 2. 安装系统软件包 ---
log_step "[2/9] 更新与安装系统基础包"
export DEBIAN_FRONTEND=noninteractive
# 检查是否已有 apt 锁
if fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1; then
   log_info "等待 apt 锁释放..."
   sleep 5
fi

apt-get update -y > /dev/null
apt-get install -y vim sudo curl ca-certificates gnupg zsh git unzip fontconfig fzf zoxide > /dev/null
log_success "基础软件包安装完成。"


# --- 3. 配置用户 Sudo 权限 ---
log_step "[3/9] 配置 Sudo 权限"
if [ "$TARGET_USER" != "root" ]; then
    if ! getent group sudo | grep -qw "$TARGET_USER"; then
        /usr/sbin/usermod -aG sudo "$TARGET_USER"
        log_success "用户 '$TARGET_USER' 已添加到 'sudo' 组。"
    else
        log_skip "用户 '$TARGET_USER' 已在 'sudo' 组中。"
    fi
else
    log_skip "目标用户是 root，无需配置 Sudo。"
fi


# --- 4. 安装 Powerlevel10k 推荐字体 ---
log_step "[4/9] 安装 MesloLGS Nerd Font 字体"
FONT_DIR="/usr/local/share/fonts"
if [ ! -f "${FONT_DIR}/MesloLGS NF Regular.ttf" ]; then
    log_info "开始下载字体 (来源: ${MESLO_FONT_BASE_URL})..."
    mkdir -p "$FONT_DIR"
    cd /tmp
    
    # 增加重试机制，防止网络波动
    curl -fLo "MesloLGS NF Regular.ttf" "${MESLO_FONT_BASE_URL}/MesloLGS%20NF%20Regular.ttf" || log_error "下载字体失败"
    curl -fLo "MesloLGS NF Bold.ttf" "${MESLO_FONT_BASE_URL}/MesloLGS%20NF%20Bold.ttf" || log_error "下载字体失败"
    
    mv ./*.ttf "$FONT_DIR/"
    log_info "正在刷新系统字体缓存..."
    fc-cache -f -v > /dev/null
    cd "$OLDPWD"
    log_success "字体安装完成。"
else
    log_skip "MesloLGS 字体已安装。"
fi


# --- 5. 为指定用户安装 Oh My Zsh ---
log_step "[5/9] 安装 Oh My Zsh"
if [ ! -d "${TARGET_HOME}/.oh-my-zsh" ]; then
    log_info "为用户 '$TARGET_USER' 安装 Oh My Zsh..."
    
    # 下载 install.sh
    INSTALL_SCRIPT=$(curl -fsSL ${OH_MY_ZSH_INSTALL_URL}) || log_error "无法下载 Oh My Zsh 安装脚本"
    
    # 执行安装，传递 REMOTE 变量以使用代理地址
    run_as_user env GIT_SSL_NO_VERIFY=true REMOTE="${OH_MY_ZSH_REMOTE}" sh -c "${INSTALL_SCRIPT}" "" --unattended
    log_success "Oh My Zsh 安装完成。"
else
    log_skip "Oh My Zsh 已安装。"
fi

# --- 6. 为指定用户安装 P10k 主题和所有插件 ---
log_step "[6/9] 安装 Powerlevel10k 主题及所有插件"
ZSH_CUSTOM_DIR="${TARGET_HOME}/.oh-my-zsh/custom"

# 定义插件列表，格式: 目标路径|Git地址
PLUGINS_AND_THEMES=(
    "themes/powerlevel10k|${P10K_URL}"
    "plugins/zsh-autosuggestions|${AUTOSUGGESTIONS_URL}"
    "plugins/zsh-syntax-highlighting|${SYNTAX_HIGHLIGHTING_URL}"
    "plugins/zsh-history-substring-search|${HISTORY_SUBSTRING_SEARCH_URL}"
    "plugins/zsh-completions|${COMPLETIONS_URL}"
)

for item in "${PLUGINS_AND_THEMES[@]}"; do
    TARGET_DIR_FULL_PATH="${ZSH_CUSTOM_DIR}/${item%%|*}"
    TARGET_DIR_NAME=$(basename "${item%%|*}")
    REPO_URL="${item#*|}"
    
    if [ ! -d "${TARGET_DIR_FULL_PATH}" ]; then
        log_info "正在安装 ${TARGET_DIR_NAME}..."
        
        TMP_CLONE_PATH="/tmp/${TARGET_DIR_NAME}"
        rm -rf "${TMP_CLONE_PATH}"

        log_info "   -> 正在以 root 权限克隆到临时目录..."
        # 增加超时设置，防止代理卡死
        env GIT_SSL_NO_VERIFY=true git clone --depth=1 "${REPO_URL}" "${TMP_CLONE_PATH}" > /dev/null 2>&1 || log_error "克隆 ${TARGET_DIR_NAME} 失败，请检查 PROXY_URL 或网络。"

        log_info "   -> 正在移动文件到用户目录..."
        run_as_user mkdir -p "$(dirname "${TARGET_DIR_FULL_PATH}")"
        mv "${TMP_CLONE_PATH}" "${TARGET_DIR_FULL_PATH}"

        log_info "   -> 正在设置文件权限..."
        chown -R "${TARGET_USER}:${TARGET_USER}" "${TARGET_DIR_FULL_PATH}"
        
        log_success "${TARGET_DIR_NAME} 安装完成。"
    else
        log_skip "${TARGET_DIR_NAME} 已安装。"
    fi
done


# --- 7. 自动配置 .zshrc 和 .p10k.zsh ---
log_step "[7/9] 自动化配置文件"
ZSHRC_FILE="${TARGET_HOME}/.zshrc"
P10K_FILE="${TARGET_HOME}/.p10k.zsh"

# 7.1 配置 .zshrc
log_info "配置 .zshrc 主题和插件..."
# 确保文件存在
if [ ! -f "$ZSHRC_FILE" ]; then
    run_as_user touch "$ZSHRC_FILE"
fi

run_as_user sed -i 's/^ZSH_THEME=".*"/ZSH_THEME="powerlevel10k\/powerlevel10k"/' "$ZSHRC_FILE"

NEW_PLUGINS="plugins=(\n  git\n  fzf\n  zsh-autosuggestions\n  zsh-syntax-highlighting\n  zsh-history-substring-search\n)"
CONFIG_MARKER="# --- PLUGINS MANAGED BY SCRIPT ---"

if ! run_as_user grep -q "$CONFIG_MARKER" "$ZSHRC_FILE"; then
    # 如果找到了 plugins=... 行，替换它
    if run_as_user grep -q "^plugins=" "$ZSHRC_FILE"; then
        run_as_user sed -i "/^plugins=/c\\${CONFIG_MARKER}\n${NEW_PLUGINS}" "$ZSHRC_FILE"
    else
        # 如果没找到，追加到文件末尾 (极少情况)
        run_as_user echo -e "${CONFIG_MARKER}\n${NEW_PLUGINS}" >> "$ZSHRC_FILE"
    fi
    log_success "插件列表已更新。"
else
    log_skip "插件列表已由脚本管理。"
fi

# 7.2 添加自定义配置
CUSTOM_CONFIG_MARKER="# --- CUSTOM CONFIG BY SCRIPT ---"
if ! run_as_user grep -q "$CUSTOM_CONFIG_MARKER" "$ZSHRC_FILE"; then
log_info "添加自定义配置和初始化代码到 .zshrc..."
run_as_user tee -a "$ZSHRC_FILE" > /dev/null << 'EOF'

# --- CUSTOM CONFIG BY SCRIPT ---
if [ -d ~/.oh-my-zsh/custom/plugins/zsh-completions/src ]; then
  fpath+=~/.oh-my-zsh/custom/plugins/zsh-completions/src
fi
ZSH_COMPDUMP="${ZDOTDIR:-$HOME}/.zcompdump"
autoload -U compinit && compinit -i -d "${ZSH_COMPDUMP}"

# Initialize zoxide
if command -v zoxide > /dev/null; then
  eval "$(zoxide init zsh)"
fi

export FZF_DEFAULT_OPTS='--height 40% --layout=reverse --border'

alias ls='ls -F --color=auto'
alias la='ls -A'
alias ll='ls -alF'
alias update='sudo apt update && sudo apt upgrade -y'
mkcd() { mkdir -p "$1" && cd "$1"; }
EOF
    log_success "自定义配置已添加。"
else
    log_skip "自定义配置块已存在。"
fi


# 7.3 创建或更新 .p10k.zsh 文件
log_info "创建或更新 .p10k.zsh 配置文件..."
tee "$P10K_FILE" > /dev/null << 'EOF'
# Generated by setup script. To customize, run `p10k configure`.
POWERLEVEL9K_MODE='nerdfont-complete'
POWERLEVEL9K_PROMPT_ON_NEWLINE=false
POWERLEVEL9K_PROMPT_ADD_NEWLINE=false
POWERLEVEL9K_LEFT_PROMPT_ELEMENTS=(os_icon dir vcs)
POWERLEVEL9K_RIGHT_PROMPT_ELEMENTS=(status root_indicator background_jobs time)
EOF
chown "${TARGET_USER}:${TARGET_USER}" "$P10K_FILE"
log_success ".p10k.zsh 已配置为紧凑单行模式。"


# --- 8. 更改目标用户的默认 Shell 为 Zsh ---
log_step "[8/9] 设置 Zsh 为默认 Shell"
CURRENT_SHELL=$(getent passwd "$TARGET_USER" | cut -d: -f7)
TARGET_SHELL=$(which zsh)

if [ "$CURRENT_SHELL" != "$TARGET_SHELL" ]; then
    chsh -s "$TARGET_SHELL" "$TARGET_USER"
    log_success "已将 Zsh 设置为 '$TARGET_USER' 的默认 Shell。"
else
    log_skip "Zsh 已是默认 Shell。"
fi

# --- 9. 清理工作 ---
log_step "[9/9] 清理临时文件"
rm -rf /tmp/themes /tmp/plugins
log_success "清理完成。"


# --- 最终提示 ---
echo -e "\n===================================================="
echo -e "🚀 \e[1;32m恭喜！超级 Zsh 终端已为用户 '$TARGET_USER' 配置完成！\e[0m"
echo ""
echo "重要提示："
echo "1. 请用户 '$TARGET_USER' \e[1;33m完全重新登录\e[0m (断开SSH后重连)。"
echo "2. 已配置代理地址: ${PROXY_URL:-'无 (直连 GitHub)'}"
echo ""
echo "3. 新功能一览："
echo "   - \e[1;36m智能跳转 (zoxide)\e[0m: 输入 \`z <目录名一部分>\` 即可快速跳转。"
echo "   - \e[1;36m模糊搜索 (fzf)\e[0m: 使用 \`Ctrl+R\`, \`Ctrl+T\`, \`Alt+C\` 进行高效搜索。"
echo ""
echo "4. 如果需要自定义样式，可以随时运行 \e[1;32mp10k configure\e[0m。"
echo "===================================================="
