from flask import Flask, Response, request, jsonify

app = Flask("echobot")


@app.route("/api", methods=["OPTIONS"])
def options():
    return Response(status=200, headers={"accept": "application/json"})


@app.route("/api", methods=["POST"])
def hello():
    print(request.data)
    if request.is_json:
        data = request.get_json()

        if "kind" not in data:
            return Response(status=400)

        if data["kind"] == "message" and "body" in data:
            return jsonify({"body": "Yes this is flask app"})

        elif data["kind"] == "iq" and data["type"] == "get":
            if "ping" in data:
                return Response(status=204)

            elif "disco" in data:
                return jsonify(
                    {
                        "disco": {
                            "identities": [
                                {
                                    "category": "component",
                                    "type": "generic",
                                    "name": "Flask app",
                                }
                            ],
                            "features": [
                                "http://jabber.org/protocol/disco#info",
                                "http://jabber.org/protocol/disco#items",
                                "urn:xmpp:ping",
                            ],
                        }
                    }
                )

            elif "items" in data:
                return jsonify(
                    {"items": [{"jid": "example.org", "name": "Example Dot Org"}]}
                )

            elif "version" in data:
                return jsonify({"version": {"name": "app.py", "version": "0"}})

    return Response(status=501)


if __name__ == "__main__":
    app.run()
