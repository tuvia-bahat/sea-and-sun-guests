"""מערכת רישום אורחים - מגדלי סי אנד סאן.

הרצה:  python app.py
משתני סביבה (אופציונלי):
  RECEPTION_PASSWORD  סיסמת פקידי הקבלה (ברירת מחדל: נוצרת אקראית ונשמרת ב-config.json)
  BASE_URL            הכתובת הציבורית שאליה מוביל הברקוד, למשל https://guests.example.com
  PORT                פורט (ברירת מחדל 8000)
"""
import io
import json
import os
import re
import secrets
import sqlite3
import time
from collections import defaultdict, deque
from datetime import datetime
from functools import wraps
from pathlib import Path

import qrcode
from flask import (Flask, abort, jsonify, redirect, render_template, request,
                   send_file, session, url_for)

ROOT = Path(__file__).parent
DB_PATH = ROOT / "guests.db"
CONFIG_PATH = ROOT / "config.json"


def load_config():
    cfg = {}
    if CONFIG_PATH.exists():
        cfg = json.loads(CONFIG_PATH.read_text(encoding="utf-8"))
    changed = False
    if "secret_key" not in cfg:
        cfg["secret_key"] = secrets.token_hex(32)
        changed = True
    if "reception_password" not in cfg:
        cfg["reception_password"] = secrets.token_urlsafe(8)
        changed = True
    if changed:
        CONFIG_PATH.write_text(json.dumps(cfg, indent=2), encoding="utf-8")
    if os.environ.get("RECEPTION_PASSWORD"):
        cfg["reception_password"] = os.environ["RECEPTION_PASSWORD"]
    return cfg


CFG = load_config()
app = Flask(__name__)
app.secret_key = os.environ.get("SECRET_KEY") or CFG["secret_key"]
app.config.update(SESSION_COOKIE_HTTPONLY=True, SESSION_COOKIE_SAMESITE="Lax",
                  PERMANENT_SESSION_LIFETIME=60 * 60 * 12)


# ---------- מסד נתונים ----------
def db():
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    return conn


def init_db():
    with db() as c:
        c.execute("""CREATE TABLE IF NOT EXISTS visitors (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            token TEXT UNIQUE NOT NULL,
            plate TEXT NOT NULL,
            phone TEXT NOT NULL,
            host TEXT NOT NULL,
            status TEXT NOT NULL DEFAULT 'pending',
            created_at TEXT NOT NULL,
            handled_at TEXT,
            handled_by TEXT)""")
        c.execute("CREATE INDEX IF NOT EXISTS idx_status ON visitors(status, created_at)")


def now():
    return datetime.now().isoformat(timespec="seconds")


# ---------- אימות קלט ----------
def clean_plate(v):
    digits = re.sub(r"\D", "", v or "")
    return digits if 5 <= len(digits) <= 8 else None


def clean_phone(v):
    digits = re.sub(r"[\s\-]", "", v or "")
    if digits.startswith("+972"):
        digits = "0" + digits[4:]
    return digits if re.fullmatch(r"0\d{8,9}", digits) else None


def clean_host(v):
    v = re.sub(r"\s+", " ", (v or "")).strip()
    return v if 2 <= len(v) <= 80 else None


# ---------- הגבלת קצב (מניעת ספאם) ----------
_hits = defaultdict(deque)


def rate_limited(key, limit=5, window=600):
    q, t = _hits[key], time.time()
    while q and q[0] < t - window:
        q.popleft()
    if len(q) >= limit:
        return True
    q.append(t)
    return False


# ---------- צד האורח ----------
@app.get("/")
def guest_form():
    return render_template("guest.html")


@app.post("/api/register")
def register():
    ip = request.headers.get("X-Forwarded-For", request.remote_addr).split(",")[0].strip()
    if rate_limited(ip):
        return jsonify(error="נשלחו יותר מדי רישומים. נא לפנות לפקיד הקבלה."), 429
    data = request.get_json(silent=True) or {}
    plate, phone, host = clean_plate(data.get("plate")), clean_phone(data.get("phone")), clean_host(data.get("host"))
    errors = {}
    if not plate:
        errors["plate"] = "מספר רכב לא תקין (5-8 ספרות)"
    if not phone:
        errors["phone"] = "מספר טלפון לא תקין"
    if not host:
        errors["host"] = "נא לציין למי אתם מגיעים"
    if errors:
        return jsonify(error="נא לתקן את השדות המסומנים", fields=errors), 400
    token = secrets.token_urlsafe(12)
    with db() as c:
        c.execute("INSERT INTO visitors (token, plate, phone, host, created_at) VALUES (?,?,?,?,?)",
                  (token, plate, phone, host, now()))
    return jsonify(token=token)


@app.get("/api/status/<token>")
def status(token):
    with db() as c:
        r = c.execute("SELECT status FROM visitors WHERE token=?", (token,)).fetchone()
    if not r:
        abort(404)
    return jsonify(status=r["status"])


# ---------- צד הקבלה ----------
def reception_only(f):
    @wraps(f)
    def wrapper(*a, **kw):
        if not session.get("reception"):
            if request.path.startswith("/api/"):
                return jsonify(error="unauthorized"), 401
            return redirect(url_for("login"))
        return f(*a, **kw)
    return wrapper


@app.route("/reception/login", methods=["GET", "POST"])
def login():
    error = None
    if request.method == "POST":
        ip = request.remote_addr
        if rate_limited("login:" + ip, limit=10, window=600):
            error = "יותר מדי ניסיונות. נסו שוב בעוד כמה דקות."
        elif secrets.compare_digest(request.form.get("password", ""), CFG["reception_password"]):
            session.permanent = True
            session["reception"] = True
            return redirect(url_for("reception"))
        else:
            error = "סיסמה שגויה"
    return render_template("login.html", error=error)


@app.get("/reception/logout")
def logout():
    session.clear()
    return redirect(url_for("login"))


@app.get("/reception")
@reception_only
def reception():
    return render_template("reception.html")


@app.get("/api/visitors")
@reception_only
def list_visitors():
    today = datetime.now().strftime("%Y-%m-%d")
    with db() as c:
        pending = c.execute("SELECT * FROM visitors WHERE status='pending' ORDER BY created_at").fetchall()
        done = c.execute("SELECT * FROM visitors WHERE status!='pending' AND created_at>=? "
                         "ORDER BY handled_at DESC LIMIT 200", (today,)).fetchall()
    strip = lambda r: {k: r[k] for k in ("id", "plate", "phone", "host", "status", "created_at", "handled_at")}
    return jsonify(pending=[strip(r) for r in pending], done=[strip(r) for r in done])


@app.post("/api/visitors/<int:vid>/<action>")
@reception_only
def handle(vid, action):
    new_status = {"enter": "entered", "reject": "rejected", "undo": "pending"}.get(action)
    if not new_status:
        abort(404)
    with db() as c:
        c.execute("UPDATE visitors SET status=?, handled_at=? WHERE id=?",
                  (new_status, None if new_status == "pending" else now(), vid))
    return jsonify(ok=True)


# ---------- ברקוד ----------
def guest_url():
    return os.environ.get("BASE_URL") or request.host_url


@app.get("/qr.png")
def qr_png():
    img = qrcode.make(guest_url(), box_size=12, border=2,
                      error_correction=qrcode.constants.ERROR_CORRECT_Q)
    buf = io.BytesIO()
    img.save(buf, "PNG")
    buf.seek(0)
    return send_file(buf, mimetype="image/png")


@app.get("/reception/qr")
@reception_only
def qr_print():
    return render_template("qr.html", url=guest_url())


if __name__ == "__main__":
    init_db()
    port = int(os.environ.get("PORT", 8000))
    print(f"\nסיסמת קבלה: {CFG['reception_password']}")
    print(f"טופס אורחים:  http://localhost:{port}/")
    print(f"מסך קבלה:     http://localhost:{port}/reception\n")
    from waitress import serve
    serve(app, host="0.0.0.0", port=port)
