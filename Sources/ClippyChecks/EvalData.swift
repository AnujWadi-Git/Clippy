import Foundation

/// Realistic clipboard corpus + paraphrased queries for measuring retrieval quality. `expect` lists acceptable item keys.
enum EvalData {
    static let items: [(key: String, text: String)] = [
        ("git-undo", "git reset --soft HEAD~1"), ("compose", "docker compose up -d"), ("kill-port", "lsof -ti:3000 | xargs kill -9"),
        ("npm-dev", "npm run dev"), ("ffmpeg", "brew install ffmpeg"), ("ssh", "ssh -i ~/.ssh/id_ed25519 ubuntu@10.0.4.17"),
        ("kubectl", "kubectl get pods -n production"), ("find-del", "find . -name '*.log' -delete"),
        ("gh-repo", "https://github.com/AnujWadi-Git/Clippy"), ("so-undo", "https://stackoverflow.com/questions/12345/how-to-undo-last-git-commit"),
        ("amazon", "https://www.amazon.jobs/en/jobs/2718281/software-development-engineer"), ("compose-docs", "https://docs.docker.com/compose/compose-file/"),
        ("stripe", "https://api.stripe.com/v1/charges"), ("linear", "https://linear.app/acme/issue/ENG-482/fix-login-redirect"),
        ("youtube", "https://www.youtube.com/watch?v=dQw4w9WgXcQ"),
        ("py-json", "import json\nwith open('config.json') as f:\n    data = json.load(f)\nprint(data['name'])"),
        ("swift-add", "func add(_ a: Int, _ b: Int) -> Int {\n    return a + b\n}"),
        ("js-fetch", "const res = await fetch('/api/users');\nconst users = await res.json();"),
        ("sql-select", "SELECT id, email FROM users WHERE active = true ORDER BY created_at DESC;"),
        ("json-config", "{\"port\":8080,\"debug\":true,\"db\":{\"host\":\"localhost\"}}"),
        ("py-trace", "Traceback (most recent call last):\n  File \"app.py\", line 42, in login\n    user = db.get(user_id)\nKeyError: 'user_id'"),
        ("swift-err", "error: cannot find 'fetchUser' in scope"),
        ("js-err", "TypeError: Cannot read properties of undefined (reading 'map')"),
        ("home-addr", "742 Evergreen Terrace, Springfield, OR 97477"), ("goog-addr", "1600 Amphitheatre Parkway, Mountain View, CA 94043"),
        ("phone-us", "+1 (415) 555-0132"), ("phone-uk", "+44 20 7946 0958"),
        ("email-me", "anuj@example.com"), ("email-bill", "billing@acme-corp.io"),
        ("notes-roadmap", "Meeting notes: Q3 roadmap review, action items: finalize pricing, ship onboarding, hire designer"),
        ("passport", "Reminder: renew passport before March, appointment at consulate on the 14th"),
        ("send-file", "hey can u send that file i need it rn"),
        ("support-reply", "Thanks for your patience! We've escalated your ticket to our engineering team and will update you within 24 hours."),
        ("wifi-note", "Guest wifi details for the office are written on the whiteboard in the kitchen"),
        ("cover-letter", "Dear hiring manager, I am excited to apply for the software engineer position at your company."),
        ("groceries", "Grocery list: oat milk, eggs, spinach, sourdough, coffee beans"),
        ("flight", "Flight AA 2231 departs SFO 7:45am Tuesday, confirmation code in email"),
        ("path-mem", "/Users/anuj/Projects/Clippy/Sources/ClippyCore/AI/MemorySearch.swift"),
        ("regex-email", "^[\\w.+-]+@[\\w-]+\\.[\\w.]+$"), ("cron", "0 3 * * 1-5"),
        ("sql-alter", "ALTER TABLE users ADD COLUMN last_login TIMESTAMP;"),
    ]

    static let queries: [(q: String, expect: Set<String>)] = [
        ("how do I undo my last commit", ["git-undo", "so-undo"]), ("kill whatever is using port 3000", ["kill-port"]),
        ("start my containers", ["compose"]), ("run the dev server", ["npm-dev"]), ("install video encoder", ["ffmpeg"]),
        ("log into the production server", ["ssh"]), ("list running pods", ["kubectl"]), ("delete all log files", ["find-del"]),
        ("the repo for clippy", ["gh-repo"]), ("docs for compose file format", ["compose-docs"]),
        ("amazon SDE job posting", ["amazon"]), ("stripe charges endpoint", ["stripe"]),
        ("linear ticket about login redirect", ["linear"]), ("that video I wanted to watch", ["youtube"]),
        ("python code to load a json file", ["py-json"]), ("function to add two numbers in swift", ["swift-add"]),
        ("how I call an api from javascript", ["js-fetch"]), ("query to get all active users", ["sql-select"]),
        ("app config settings", ["json-config"]), ("the login bug stack trace", ["py-trace"]),
        ("swift compile error about missing function", ["swift-err"]), ("javascript undefined map error", ["js-err"]),
        ("my home address", ["home-addr"]), ("google office location", ["goog-addr"]),
        ("phone number for the US", ["phone-us"]), ("UK number", ["phone-uk"]), ("my email", ["email-me"]),
        ("billing contact", ["email-bill"]), ("what did we discuss about roadmap", ["notes-roadmap"]),
        ("passport appointment", ["passport"]), ("message asking for a file", ["send-file"]),
        ("support reply about escalation", ["support-reply"]), ("guest wifi info", ["wifi-note"]),
        ("cover letter intro", ["cover-letter"]), ("what to buy at the store", ["groceries"]),
        ("my flight details", ["flight"]), ("file path to memory search", ["path-mem"]),
        ("regex for validating emails", ["regex-email"]), ("weekday 3am schedule", ["cron"]),
        ("add a column to users table", ["sql-alter"]),
    ]

    static let negatives = ["quantum physics lecture", "chocolate cake recipe", "stock price of tesla", "football scores", "how to knit a scarf", "zebra spaceship"]
}
