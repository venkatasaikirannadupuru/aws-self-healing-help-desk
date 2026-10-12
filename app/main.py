from flask import Flask, render_template, request, redirect, url_for

app = Flask(__name__, template_folder='../templates', static_folder='../static')

tickets = []
next_ticket_id = 1


@app.route("/")
def home():
    return render_template("index.html", tickets=tickets)


@app.route("/tickets", methods=["POST"])
def create_ticket():
    global next_ticket_id

    title = request.form.get("title", "").strip()
    description = request.form.get("description", "").strip()

    if not title or not description:
        return "Title and description are required.", 400

    ticket = {
        "id": next_ticket_id,
        "title": title,
        "description": description,
        "status": "Open",
    }

    tickets.append(ticket)
    next_ticket_id += 1

    return redirect(url_for("home"))


@app.route("/health")
def health():
    return {"status": "healthy"}, 200


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000, debug=False)
