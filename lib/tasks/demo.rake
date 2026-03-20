# frozen_string_literal: true
#
# Demo rake task: simulate a realistic SengClaw coding-agent execution.
#
# SCENARIO: 修复官网底部3处旧logo（emoji → 新logo图片）
#
# INTERACTIVE FLOW:
#   1. rake demo:phase1  — SengClaw 分析需求 → 只改第1处（CTA区域）→ 启动临时ngrok → elicitation请求review
#   2. (用户反馈: footer还有2处没改)
#   3. rake demo:phase2  — SengClaw 继续改剩余2处 → 再次elicitation
#   4. (用户确认: LGTM)
#   5. rake demo:phase3  — SengClaw commit + close issue
#
# Usage:
#   rake demo:phase1               — 第一阶段（只改1处，等待反馈）
#   rake demo:phase2               — 第二阶段（改剩余2处）
#   rake demo:phase3               — 第三阶段（commit + close issue）
#   rake demo:reset                — 还原官网代码到初始状态（3处都是旧logo），杀掉临时ngrok
#   rake demo:status               — 查看当前 AgentTask / ngrok 状态

namespace :demo do

  # ─── 临时 ngrok 隧道管理 ──────────────────────────────────────────────────────
  DEMO_NGROK_PID_FILE = Rails.root.join("tmp", "demo_ngrok.pid").to_s
  DEMO_NGROK_URL_FILE = Rails.root.join("tmp", "demo_ngrok_url.txt").to_s
  DEMO_NGROK_API_PORT = 4042  # 第三个 ngrok 进程用这个 web API 端口

  def start_demo_ngrok!
    puts "  🌐 启动临时 ngrok 隧道..."
    # 先确认没有旧进程
    stop_demo_ngrok!

    # 后台起 ngrok，让它用随机域名
    pid = spawn("ngrok http 3002 --log=stdout 2>/dev/null",
      out: "/dev/null", err: "/dev/null")
    Process.detach(pid)
    File.write(DEMO_NGROK_PID_FILE, pid.to_s)

    # 等待隧道建立，轮询 API
    url = nil
    10.times do
      sleep 1
      [4040, 4041, 4042, 4043].each do |port|
        next if port == 4040 || port == 4041  # 那两个是固定的
        begin
          raw = URI.open("http://localhost:#{port}/api/tunnels", read_timeout: 2).read
          data = JSON.parse(raw)
          tunnels = data["tunnels"] || []
          # 找不是 harvest.ngrok.app 也不是 sengclaw.ngrok.dev 的
          t = tunnels.find { |x|
            x["public_url"]&.include?("ngrok") &&
            !x["public_url"].include?("sengclaw") &&
            !x["public_url"].include?("harvest")
          }
          if t
            url = t["public_url"]
            File.write(DEMO_NGROK_URL_FILE, url)
            puts "  ✅ 临时预览地址: #{url}"
            return url
          end
        rescue => e
          # keep polling
        end
      end
    end

    # fallback: 用 sengclaw.ngrok.dev
    url = "https://sengclaw.ngrok.dev"
    File.write(DEMO_NGROK_URL_FILE, url)
    puts "  ⚠️  未能获取临时域名，使用默认: #{url}"
    url
  end

  def stop_demo_ngrok!
    if File.exist?(DEMO_NGROK_PID_FILE)
      pid = File.read(DEMO_NGROK_PID_FILE).strip.to_i
      Process.kill("TERM", pid) rescue nil
      File.delete(DEMO_NGROK_PID_FILE) rescue nil
    end
    File.delete(DEMO_NGROK_URL_FILE) rescue nil
  end

  def demo_ngrok_url
    return File.read(DEMO_NGROK_URL_FILE).strip if File.exist?(DEMO_NGROK_URL_FILE)
    "https://sengclaw.ngrok.dev"
  end

  # ─── Linear activity helper ───────────────────────────────────────────────────
  def post_activity(token, session_id, type:, body: nil, action_name: nil, parameter: nil, result: nil)
    LinearActivityService.new(
      access_token:     token,
      agent_session_id: session_id,
      type:             type,
      body:             body,
      action_name:      action_name,
      parameter:        parameter,
      result:           result
    ).call
    label = body ? body.split("\n").first[0..60] : action_name
    puts "  ✅ [#{type}] #{label}"
  rescue => e
    puts "  ❌ [#{type}] failed: #{e.message}"
    raise
  end

  def load_task_and_token
    task = AgentTask.where(status: ["dispatched", "pending"]).last || AgentTask.last
    raise "No AgentTask found — create a Linear issue and assign to SengClaw Dev first!" unless task
    installation = LinearInstallation.find_by!(install_token: task.install_token)
    raise "No access_token found" unless installation.access_token.present?
    [task, installation.access_token]
  end

  # ─────────────────────────────────────────────────────────────────────────────
  desc "Phase 1: 分析需求 → 读文件 → 只修第1处(CTA) → 临时ngrok → 请求review"
  task phase1: :environment do
    task, token = load_task_and_token
    sid = task.agent_session_id

    puts ""
    puts "🦐 SengClaw Demo — Phase 1"
    puts "   session: #{sid}"
    puts "   issue:   #{task.issue_id}"
    puts ""

    # Step 1: 收到任务，分析需求
    puts "Step 1: 分析需求..."
    post_activity(token, sid,
      type: "thought",
      body: "收到任务！正在分析 issue 需求...\n\n**目标**：修复官网底部 3 处旧 logo（当前用的是 🦐 emoji），统一替换为新的 `sengclaw-logo.png` 图片文件。\n\n先读取官网首页源码，定位所有需要替换的位置。"
    )
    sleep 1.5

    # Step 2: 读取官网代码
    puts "Step 2: 读取官网代码..."
    post_activity(token, sid,
      type: "action",
      action_name: "ReadFile",
      parameter: "app/views/home/index.html.erb",
      result: "Read 430 lines — found logo references in CTA section, footer brand, and form footer text"
    )
    sleep 1

    # Step 3: 分析发现3处
    post_activity(token, sid,
      type: "thought",
      body: "代码读取完毕，定位到 **3 处旧 logo**：\n\n1. **CTA 区域**（第 288 行）：`<div class=\"w-20 h-20...\">🦐</div>`\n2. **Footer 品牌区**（第 356 行）：`<span class=\"text-2xl\">🦐</span>`\n3. **表单底部文字**（第 312 行）：`我们会在 24 小时内联系你 🦐`\n\n开始逐一替换..."
    )
    sleep 1.5

    # Step 4: 修改文件（只改第1处）
    puts "Step 4: 修改 CTA 区域（第1处）..."
    post_activity(token, sid,
      type: "action",
      action_name: "EditFile",
      parameter: "app/views/home/index.html.erb (line 288: CTA section logo)",
      result: "Replaced <div>🦐</div> with <%= image_tag 'sengclaw-logo.png', class: 'w-20 h-20 object-contain' %>"
    )

    # ── 实际修改代码（只改第1处）─────────────────────────────────────
    home_view = Rails.root.join("app/views/home/index.html.erb").to_s
    content = File.read(home_view)
    # CTA 区域的 emoji（大图标那个）
    content = content.gsub(
      '<div class="w-20 h-20 rounded-2xl bg-primary/10 flex items-center justify-center mx-auto mb-6 text-4xl">🦐</div>',
      '<div class="w-20 h-20 rounded-2xl bg-primary/10 flex items-center justify-center mx-auto mb-6"><%= image_tag "sengclaw-logo.png", class: "w-14 h-14 object-contain", alt: "大胜龙虾" %></div>'
    )
    File.write(home_view, content)
    puts "  [CODE] CTA logo 已修改"

    sleep 1

    # Step 5: 启动临时 ngrok
    puts "Step 5: 启动临时预览..."
    preview_url = start_demo_ngrok!
    sleep 1

    post_activity(token, sid,
      type: "action",
      action_name: "StartPreview",
      parameter: "ngrok http 3002",
      result: "Preview started at #{preview_url}"
    )
    sleep 0.5

    post_activity(token, sid,
      type: "thought",
      body: "第 1 处已修复，临时预览地址就绪：**#{preview_url}**\n\n请在该链接查看 CTA 区域的 logo 效果，确认无误后我继续处理其余两处。"
    )
    sleep 0.5

    # Step 6: Elicitation — 请求 review
    puts "Step 6: 请求 review..."
    post_activity(token, sid,
      type: "elicitation",
      body: "✅ **第 1 处已修复，请先 review**\n\n🔗 **预览地址**：[#{preview_url}](#{preview_url})\n\n**已完成**：\n- CTA 区域大 logo：`🦐` emoji → `sengclaw-logo.png` 图片 ✅\n\n**待处理**（还有 2 处）：\n- Footer 品牌 logo\n- 表单底部文字中的 emoji\n\n请先查看预览，确认 CTA 区域效果满意后回复，我继续修复剩余两处。"
    )

    puts ""
    puts "🎬 Phase 1 完成！"
    puts "   预览地址: #{preview_url}"
    puts "   等待用户在 Linear 回复反馈..."
    puts ""
    puts "👉 下一步: rake demo:phase2 （用户反馈后执行）"
  end

  # ─────────────────────────────────────────────────────────────────────────────
  desc "Phase 2: 修复剩余2处logo → 再次请求确认"
  task phase2: :environment do
    task, token = load_task_and_token
    sid = task.agent_session_id
    preview_url = demo_ngrok_url

    puts ""
    puts "🦐 SengClaw Demo — Phase 2"
    puts ""

    # Step 1: 收到反馈，继续
    post_activity(token, sid,
      type: "thought",
      body: "收到你的反馈！footer 还有 2 处没改，马上处理。\n\n继续修复：\n- Footer 品牌区域的 logo\n- 表单底部文字中的 emoji"
    )
    sleep 1.5

    # Step 2: 修改 Footer 品牌 logo
    post_activity(token, sid,
      type: "action",
      action_name: "EditFile",
      parameter: "app/views/home/index.html.erb (line 356: footer brand logo)",
      result: "Replaced <span>🦐</span> with <%= image_tag 'sengclaw-logo.png', class: 'w-8 h-8 object-contain' %>"
    )

    # ── 实际修改代码（第2处：footer 品牌区）──────────────────────────
    home_view = Rails.root.join("app/views/home/index.html.erb").to_s
    content = File.read(home_view)
    # 精确替换 footer 里的 emoji（直接匹配那行）
    content = content.gsub(
      '          <span class="text-2xl">🦐</span>',
      '          <%= image_tag "sengclaw-logo.png", class: "w-8 h-8 object-contain", alt: "大胜龙虾" %>'
    )
    File.write(home_view, content)
    puts "  [CODE] Footer 品牌 logo 已修改"

    sleep 1

    # Step 3: 修改表单底部文字
    post_activity(token, sid,
      type: "action",
      action_name: "EditFile",
      parameter: "app/views/home/index.html.erb (line 312: form footer text)",
      result: "Replaced inline 🦐 emoji in footer text with sengclaw-logo.png inline image"
    )

    # ── 实际修改代码（第3处）──────────────────────────────────────────
    content = File.read(home_view)
    content = content.gsub(
      '我们会在 24 小时内联系你 🦐',
      '我们会在 24 小时内联系你 <%= image_tag "sengclaw-logo.png", class: "w-4 h-4 object-contain inline-block align-middle", alt: "SengClaw" %>'
    )
    File.write(home_view, content)
    puts "  [CODE] 表单底部文字 logo 已修改"

    sleep 1

    post_activity(token, sid,
      type: "thought",
      body: "3 处全部修复完毕！✅\n\n预览地址还是有效的：**#{preview_url}**\n\n刷新页面查看完整效果。"
    )
    sleep 0.5

    # Step 4: 再次请求确认
    post_activity(token, sid,
      type: "elicitation",
      body: "✅ **全部 3 处已修复，请最终确认**\n\n🔗 **预览地址**：[#{preview_url}](#{preview_url})\n\n**修复清单**：\n- CTA 大 logo ✅\n- Footer 品牌 logo ✅\n- 表单底部文字 ✅\n\n请刷新预览页面查看完整效果。确认无问题后回复，我马上提交代码并关闭 issue。"
    )

    puts ""
    puts "🎬 Phase 2 完成！"
    puts "   所有3处logo均已修复"
    puts "   预览: #{preview_url}"
    puts ""
    puts "👉 下一步: rake demo:phase3 （用户确认后执行）"
  end

  # ─────────────────────────────────────────────────────────────────────────────
  desc "Phase 3: Commit + close issue"
  task phase3: :environment do
    task, token = load_task_and_token
    sid = task.agent_session_id

    puts ""
    puts "🦐 SengClaw Demo — Phase 3"
    puts ""

    post_activity(token, sid,
      type: "thought",
      body: "收到确认！准备提交代码并关闭 issue。"
    )
    sleep 1

    # Git commit
    post_activity(token, sid,
      type: "action",
      action_name: "GitCommit",
      parameter: "git commit -am 'fix: replace legacy emoji logos with sengclaw-logo.png in homepage'",
      result: "Committed: a3f8c12 — fix: replace legacy emoji logos with sengclaw-logo.png in homepage\n3 files changed, 3 insertions(+), 3 deletions(-)"
    )
    sleep 1

    # 最终 response
    post_activity(token, sid,
      type: "response",
      body: "🎉 **全部完成！**\n\n```\ncommit a3f8c12\nfix: replace legacy emoji logos with sengclaw-logo.png in homepage\n\n- CTA section: 🦐 → sengclaw-logo.png (w-14 h-14)\n- Footer brand: 🦐 → sengclaw-logo.png (w-8 h-8)\n- Form footer: 🦐 → sengclaw-logo.png (w-4 h-4 inline)\n```\n\nIssue 已关闭。✅"
    )

    task.mark_done! rescue nil

    # Close issue in Linear
    puts "  Closing Linear issue..."
    done_state_id = fetch_done_state_id(token)
    if done_state_id
      update_issue_state(token, task.issue_id, done_state_id)
      puts "  ✅ Issue marked as Done in Linear"
    else
      puts "  ⚠️  Could not find Done state"
    end

    # 关掉临时 ngrok
    stop_demo_ngrok!
    puts "  ✅ 临时 ngrok 隧道已关闭"

    puts ""
    puts "🦐 演示完毕！Issue 已关闭。"
  end

  # ─────────────────────────────────────────────────────────────────────────────
  desc "Reset: 还原官网代码到初始状态（3处旧logo emoji）+ 停止临时ngrok"
  task reset: :environment do
    puts "🔄 还原官网代码..."

    home_view = Rails.root.join("app/views/home/index.html.erb").to_s
    content = File.read(home_view)

    # 还原 CTA 区域（phase1 修改的那处）
    content = content.gsub(
      '<div class="w-20 h-20 rounded-2xl bg-primary/10 flex items-center justify-center mx-auto mb-6"><%= image_tag "sengclaw-logo.png", class: "w-14 h-14 object-contain", alt: "大胜龙虾" %></div>',
      '<div class="w-20 h-20 rounded-2xl bg-primary/10 flex items-center justify-center mx-auto mb-6 text-4xl">🦐</div>'
    )

    # 还原 Footer 品牌 logo（phase2 修改的）
    # 注意：精确匹配 footer 里那行（10 spaces），不动 navbar
    content = content.gsub(
      '          <%= image_tag "sengclaw-logo.png", class: "w-8 h-8 object-contain", alt: "大胜龙虾" %>',
      '          <span class="text-2xl">🦐</span>'
    )

    # 还原 表单底部文字（phase2 修改的）
    content = content.gsub(
      '我们会在 24 小时内联系你 <%= image_tag "sengclaw-logo.png", class: "w-4 h-4 object-contain inline-block align-middle", alt: "🦐" %>',
      '我们会在 24 小时内联系你 🦐'
    )

    File.write(home_view, content)
    puts "  ✅ 官网代码已还原（3处都是旧emoji logo，navbar保持新logo）"

    stop_demo_ngrok!
    puts "  ✅ 临时 ngrok 已停止"
    puts ""
    puts "🎬 可以重新开始演示了！"
  end

  # ─────────────────────────────────────────────────────────────────────────────
  desc "Status: 查看当前 AgentTask 和 ngrok 状态"
  task status: :environment do
    puts ""
    puts "=== Demo Status ==="
    task = AgentTask.last
    if task
      puts "AgentTask: #{task.id} | status: #{task.status}"
      puts "  session: #{task.agent_session_id}"
      puts "  issue:   #{task.issue_id}"
    else
      puts "No AgentTask found"
    end
    puts ""
    puts "ngrok URL: #{demo_ngrok_url}"
    puts "ngrok PID file: #{File.exist?(DEMO_NGROK_PID_FILE) ? File.read(DEMO_NGROK_PID_FILE).strip : 'not running'}"
    puts ""
  end

  # ─────────────────────────────────────────────────────────────────────────────
  # Helpers

  def fetch_done_state_id(token)
    query = <<~GRAPHQL
      query { workflowStates(filter: { type: { eq: "completed" } }) { nodes { id name type } } }
    GRAPHQL
    uri = URI("https://api.linear.app/graphql")
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    req = Net::HTTP::Post.new(uri)
    req["Content-Type"]  = "application/json"
    req["Authorization"] = token
    req.body = { query: query }.to_json
    res = http.request(req)
    data = JSON.parse(res.body)
    states = data.dig("data", "workflowStates", "nodes") || []
    states.find { |s| s["type"] == "completed" }&.dig("id")
  rescue => e
    puts "  ⚠️  fetch_done_state_id: #{e.message}"
    nil
  end

  def update_issue_state(token, issue_id, state_id)
    mutation = <<~GRAPHQL
      mutation UpdateIssue($id: String!, $stateId: String!) {
        issueUpdate(id: $id, input: { stateId: $stateId }) { success }
      }
    GRAPHQL
    uri = URI("https://api.linear.app/graphql")
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    req = Net::HTTP::Post.new(uri)
    req["Content-Type"]  = "application/json"
    req["Authorization"] = token
    req.body = { query: mutation, variables: { id: issue_id, stateId: state_id } }.to_json
    res = http.request(req)
    JSON.parse(res.body).dig("data", "issueUpdate", "success")
  rescue => e
    puts "  ⚠️  update_issue_state: #{e.message}"
    false
  end
end
