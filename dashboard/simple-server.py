#!/usr/bin/env python3

import http.server
import socketserver
import json
import subprocess
import os
from pathlib import Path

class SimpleStatusHandler(http.server.SimpleHTTPRequestHandler):
    def do_GET(self):
        if self.path == '/api/status':
            self.send_response(200)
            self.send_header('Content-type', 'application/json')
            self.send_header('Access-Control-Allow-Origin', '*')
            self.end_headers()
            
            try:
                # Run status script from project root
                project_root = Path(__file__).parent.parent
                result = subprocess.run(['./dashboard/status-api.sh'], 
                                      capture_output=True, 
                                      text=True, 
                                      cwd=str(project_root),
                                      timeout=30)
                
                if result.returncode == 0:
                    self.wfile.write(result.stdout.encode())
                else:
                    error = {"error": f"Script failed: {result.stderr}", "timestamp": "2025-06-18T19:30:00Z"}
                    self.wfile.write(json.dumps(error).encode())
            except Exception as e:
                error = {"error": str(e), "timestamp": "2025-06-18T19:30:00Z"}
                self.wfile.write(json.dumps(error).encode())
        else:
            # Serve dashboard files
            if self.path == '/':
                self.path = '/index.html'
            super().do_GET()

PORT = 8093
os.chdir(Path(__file__).parent)  # Set working directory to dashboard folder

with socketserver.TCPServer(("", PORT), SimpleStatusHandler) as httpd:
    print(f"Dashboard running at http://localhost:{PORT}")
    httpd.serve_forever()