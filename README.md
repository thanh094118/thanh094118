# SOC Intern — Portfolio (TL;DR)
**Mục tiêu:** minh hoạ năng lực điều tra, phát hiện và tự động hoá vận hành SOC qua 3–4 project ngắn, có artifact thực thi (queries, rules, playbooks, logs, báo cáo).

---

## Kỹ năng & công nghệ chính
- SIEM / Log analysis: Splunk / ELK (searches, dashboards)  
- Detection: Sigma, YARA, Suricata rules  
- Forensics & triage: Wireshark, Volatility, Sysinternals  
- Automation & scripting: Python, PowerShell, Bash, Docker  
- Dev tools: Git, CI basics, Markdown, RFC-style notes

---

## Dự án nổi bật (tóm tắt nhanh)
1. **RDP Brute-Force Detection** — *role: author*  
   - Mục tiêu: phát hiện và giảm false positives cho RDP brute-force.  
   - Kết quả: Sigma rule + Splunk query + test logs (10k events), precision ↑.  
   - Thư mục: `/projects/rdp-detection/` — xem `README.md`, `sigma/rdp_bruteforce.yml`, `tests/`.

2. **Windows Memory Triage (Incident)** — *role: lead investigator (intern)*  
   - Mục tiêu: thu thập evidence từ memory dump, xác định process injection.  
   - Kết quả: forensic report (TL;DR), Volatility commands + timelines.  
   - Thư mục: `/projects/win-memory/` — có `report.pdf`, `commands.txt`, `samples/`.

3. **Phishing Triage Playbook (Automation)** — *role: implementer*  
   - Mục tiêu: tự động hoá phân loại/label, enrich IP/domain, tạo case.  
   - Kết quả: Python script + example Slack alert + runbook.  
   - Thư mục: `/projects/phish-playbook/` — `run_demo.sh`, `playbook.md`, `scripts/`.

---

## Cách review nhanh (what to look for)
1. Mở mỗi `/projects/<name>/README.md` để thấy mục tiêu và bước chạy demo.  
2. Kiểm tra:
   - Detection rules (`sigma/`, `suricata/`, Splunk queries) — rõ ràng & có test cases.  
   - Artifacts: sample logs, memory dump samples, screenshots của dashboard.  
   - Playbooks & scripts: `run_demo.sh` hoặc `docker-compose.yml` để reproduce.  
   - Commit history: commit messages có ý nghĩa (feature/fix/docs).  
3. Kiểm tra `notes/` hoặc `postmortem.md` để thấy tư duy điều tra và lessons learned.

---

## Cách chạy demo (tóm tắt)
- Mỗi project chứa `README.md` riêng với bước “Quick demo”.  
- Nếu có Docker: `docker-compose up --build` → mở UI/endpoint chỉ trong README.  
- Nếu script: `chmod +x run_demo.sh && ./run_demo.sh` (mô phỏng bằng sample logs).

---

## Liên hệ
- GitHub: `github.com/<your-username>`  
- Email: `<your-email@example.com>`  
- Nếu muốn review chi tiết theo checklist (queries, false-positive analysis, test logs) — để lại comment trực tiếp trên PR hoặc mở issue trong repo.
