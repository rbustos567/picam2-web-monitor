import io
import logging
import threading
import base64
import os
from http.server import HTTPServer, BaseHTTPRequestHandler
from socketserver import ThreadingMixIn
from picamera2 import Picamera2
from picamera2.encoders import MJPEGEncoder
from picamera2.outputs import FileOutput
from libcamera import Transform

# -------------------------------------------------------------
# CREDENTIALS CONFIGURATION
# -------------------------------------------------------------
USUARIO = os.getenv("CAM_USER", "admin")      # "admin" by default if CAM_USER does not exist
PASSWORD = os.getenv("CAM_PASS", "12345")     # "12345" by default if CAM_PASS does not exist
# -------------------------------------------------------------

# Generate credential in Base64 format for HTTP Basic Auth
CRED_CORRECTAS = base64.b64encode(f"{USUARIO}:{PASSWORD}".encode('utf-8')).decode('utf-8')

PAGE = """\
<!DOCTYPE html>
<html>
<head>
    <title>Monitoreo OV5647 (Protegido)</title>
    <style>
        body { background-color: #111; color: white; text-align: center; font-family: sans-serif; margin: 0; padding: 20px; }
        img { width: 100%; max-width: 960px; height: auto; border: 3px solid #333; border-radius: 8px; }
    </style>
</head>
<body>
    <h2>Camara en Vivo (Raspberry Pi)</h2>
    <img src="stream.mjpg" />
</body>
</html>
"""

class StreamingOutput(io.BufferedIOBase):
    def __init__(self):
        self.frame = None
        self.condition = threading.Condition()

    def write(self, buf):
        with self.condition:
            self.frame = buf
            self.condition.notify_all()

class StreamingHandler(BaseHTTPRequestHandler):
    def do_AUTHHEAD(self):
        """Sends header requesting user and password"""
        self.send_response(401)
        self.send_header('WWW-Authenticate', 'Basic realm="Camera Access protected"')
        self.send_header('Content-Type', 'text/html')
        self.end_headers()
        self.wfile.write(b"Autenticacion required.")

    def authenticate(self):
        """Verify if user and password are correct"""
        auth_header = self.headers.get('Authorization')
        if auth_header is None:
            return False
        
        # Header format is: "Basic dXNlcjpwYXNz"
        try:
            auth_type, encoded_cred = auth_header.split(' ', 1)
            if auth_type.lower() == 'basic' and encoded_cred == CRED_CORRECTAS:
                return True
        except Exception:
            pass
        return False

   def do_GET(self):
        # Verify credentials before processing any petition 
        if not self.authenticate():
            self.do_AUTHHEAD()
            return

        if self.path == '/':
            self.send_response(301)
            self.send_header('Location', '/index.html')
            self.end_headers()
        elif self.path == '/index.html':
            content = PAGE.encode('utf-8')
            self.send_response(200)
            self.send_header('Content-Type', 'text/html')
            self.send_header('Content-Length', len(content))
            self.end_headers()
            self.wfile.write(content)
        elif self.path == '/stream.mjpg':
            self.send_response(200)
            self.send_header('Age', 0)
            self.send_header('Cache-Control', 'no-cache, private')
            self.send_header('Pragma', 'no-cache')
            self.send_header('Content-Type', 'multipart/x-mixed-replace; boundary=FRAME')
            self.end_headers()
            try:
                while True:
                    with output.condition:
                        output.condition.wait()
                        frame = output.frame
                    self.wfile.write(b'--FRAME\r\n')
                    self.send_header('Content-Type', 'image/jpeg')
                    self.send_header('Content-Length', len(frame))
                    self.end_headers()
                    self.wfile.write(frame)
                    self.wfile.write(b'\r\n')
            except Exception as e:
                logging.warning(f"Cliente desconectado: {e}")
        else:
            self.send_error(404)
            self.end_headers()

class ThreadedHTTPServer(ThreadingMixIn, HTTPServer):
    allow_reuse_address = True
    daemon_threads = True

# Initiate pi camera
picam2 = Picamera2()
output = StreamingOutput()

# Configure format, resolution and transform
config = picam2.create_video_configuration(
    main={
        "size": (640, 480),  # Resolutions: (1280, 720), (1920, 1080), (640, 480)
        "format": "RGB888"     # Pixel Internal Format
    },
    controls={
        "FrameRate": 6.0,     # FPS: 15.0, 25.0, 30.0, etc.
    },
    transform=Transform(hflip=0, vflip=1) # 1 to active switching horizontal/vertical
)

picam2.configure(config)

# Adjust sensor and image parameters (V4L2 Controls/libcamera) 
picam2.set_controls({
    "Brightness": 0.0,        # Brightness: from -1.0 to 1.0 (default 0.0)
    "Contrast": 1.0,          # Contrast: from 0.0 to 32.0 (default 1.0)
    "Saturation": 1.0,        # Saturation: from 0.0 to 32.0 (default 1.0)
    "Sharpness": 1.0,         # Nitidez: from 0.0 to 16.0 (default 1.0)
    "AeExposureMode": 0,      # Expore Mode: 0 (Normal), 1 (Close Exposure/Sports), 2 (Wide Open Exposure/Night)
    "AwbMode": 0              # White Balance: 0 (Auto), 1 (Incandescent), 2 (Daylight)
})

picam2.start_recording(MJPEGEncoder(), FileOutput(output))

try:
    address = ('', 8080)
    server = ThreadedHTTPServer(address, StreamingHandler)
    print("Server successfully started in port 8080")
    server.serve_forever()
finally:
    picam2.stop_recording()
