from app.main import app


def setup_function():
    app.config["TESTING"] = True


def test_home_page():
    client = app.test_client()
    response = client.get("/")
    assert response.status_code == 200
    assert b"IT Help Desk" in response.data


def test_health_endpoint():
    client = app.test_client()
    response = client.get("/health")
    assert response.status_code == 200
    assert response.json == {"status": "healthy"}


def test_create_ticket():
    client = app.test_client()
    response = client.post(
        "/tickets",
        data={
            "title": "Laptop issue",
            "description": "Laptop is not starting",
        },
        follow_redirects=True,
    )
    assert response.status_code == 200
    assert b"Laptop issue" in response.data


def test_ticket_requires_title_and_description():
    client = app.test_client()
    response = client.post("/tickets", data={"title": ""})
    assert response.status_code == 400
