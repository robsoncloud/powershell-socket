from fastapi import FastAPI, WebSocket, WebSocketDisconnect, WebSocketException
from fastapi.responses import HTMLResponse

app = FastAPI()

html = """
<!DOCTYPE html>
<html lang="en">
<head>
        <title>Websocket Demo</title>
           <!-- Bootstrap CSS -->
    <link href="https://cdn.jsdelivr.net/npm/bootstrap@5.0.2/dist/css/bootstrap.min.css" rel="stylesheet" integrity="sha384-EVSTQN3/azprG1Anm3QDgpJLIm9Nao0Yz1ztcQTwFspd3yD65VohhpuuCOmLASjC" crossorigin="anonymous">

    </head>
<body>

<div class="container m-3">
    <h1>FastAPI WebSocket</h1>
    <h2>Your ID: <span id="ws-id"></span></h2>
    <form action="" onsubmit="sendMessage(event)">
        <input type="text" class="form-control" id="messageText" autocomplete="off" />
        <button class="btn btn-outline-primary mt-2">Send</button>
    </form>
    <ul id="messages" class="mt-5"></ul>
</div>

<script>
    var client_id = Date.now()
    document.querySelector("#ws-id").textContent = client_id
    var ws = new WebSocket(`ws://localhost:8000/ws/${client_id}`);
    ws.onmessage = function(event) {
        var messages = document.getElementById('messages')
        var message = document.createElement('li')
        var content = document.createTextNode(event.data)
        message.appendChild(content)
        messages.appendChild(message)
    };
    
    function sendMessage(event) {
        var input = document.getElementById("messageText")
        ws.send(input.value)
        input.value = ""
        event.preventDefault()
    }

</script>
    
</body>
</html>
"""

class ConnectionManager:
    def __init__(self):
        self.active_connections: list[WebSocket] = []

    async def connect(self, websocket: WebSocket):
        await websocket.accept()
        self.active_connections.append(websocket)
    def disconnect(self, websocket: WebSocket):
        self.active_connections.remove(websocket)
        
    async def send_personal_message(self, message: str, websocket: WebSocket):
        await websocket.send_text(message)
    
    async def broadcast(self, message: str):
        for c in self.active_connections:
            await c.send_text(message)
            
manager = ConnectionManager()

@app.get("/")
async def root():
    return HTMLResponse(html)


@app.websocket("/ws/{client_id}")
async def websocket_endpoint(websocket: WebSocket, client_id: str):
    await manager.connect(websocket)
    try:
        while True:
            message = await websocket.receive()
            if "text" in message:
                data = message["text"]
                await manager.send_personal_message(f"You wrote: {data}", websocket)
                await manager.broadcast(f"Client #{client_id} says: {data}")
            else:
                # Handle other message types (e.g., binary, ping, close)
                print(f"Received non-text message from Client #{client_id}: {message}")
    except WebSocketDisconnect:
        manager.disconnect(websocket)
        await manager.broadcast(f"Client #{client_id} has left the chat")
    except WebSocketException as e:
        print(f"WebSocket exception: {e}")
    # except Exception as e:
    #     # Handle any other exceptions
    #     print(e)
    #     # Optionally, raise a WebSocketException to close the connection with a specific reason
    #     #raise WebSocketException(code=1000, reason="Internal server error")
    # finally:
    #     # Ensure the WebSocket is closed if an exception occurs
    #     print("finally")
    #     #await websocket.close()
        
   