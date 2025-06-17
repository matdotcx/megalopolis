#!/usr/bin/env python3
"""
Minimal VM API Server

A simple HTTP API wrapper around the existing VM CLI scripts.
Follows test-first development - implements only what tests require.
"""

import json
import os
import sys
import subprocess
from http.server import HTTPServer, BaseHTTPRequestHandler
from datetime import datetime, timezone

class MinimalVMAPIHandler(BaseHTTPRequestHandler):
    """Simple HTTP request handler for VM operations"""
    
    def do_GET(self):
        """Handle GET requests"""
        if self.path == '/health':
            self.handle_health()
        elif self.path == '/vms':
            self.handle_vms()
        elif self.path.startswith('/vms/'):
            vm_name = self.path[5:]  # Remove '/vms/' prefix
            self.handle_vm_detail(vm_name)
        else:
            self.send_error(404, "Endpoint not found")
    
    def do_POST(self):
        """Handle POST requests"""
        if self.path.startswith('/vms/') and self.path.endswith('/start'):
            vm_name = self.path[5:-6]  # Remove '/vms/' prefix and '/start' suffix
            self.handle_vm_start(vm_name)
        elif self.path.startswith('/vms/') and self.path.endswith('/stop'):
            vm_name = self.path[5:-5]  # Remove '/vms/' prefix and '/stop' suffix
            self.handle_vm_stop(vm_name)
        else:
            self.send_error(404, "Endpoint not found")
    
    def handle_health(self):
        """Handle /health endpoint"""
        response = {
            "status": "healthy",
            "message": "Minimal VM API is running",
            "timestamp": datetime.now(timezone.utc).isoformat()
        }
        
        self.send_response(200)
        self.send_header('Content-Type', 'application/json')
        self.send_header('Access-Control-Allow-Origin', '*')
        self.end_headers()
        
        self.wfile.write(json.dumps(response, indent=2).encode())
    
    def handle_vms(self):
        """Handle /vms endpoint"""
        try:
            # Get project root directory
            script_dir = os.path.dirname(os.path.abspath(__file__))
            project_root = os.path.dirname(script_dir)
            tart_bin = os.path.join(project_root, "tart-binary")
            
            # Run tart list command
            result = subprocess.run(
                [tart_bin, "list"],
                capture_output=True,
                text=True,
                timeout=10
            )
            
            vms = []
            if result.returncode == 0 and result.stdout.strip():
                # Parse tart list output
                lines = result.stdout.strip().split('\n')
                for line in lines:
                    # Skip header line
                    if line.startswith('Source'):
                        continue
                    
                    parts = line.split()
                    if len(parts) >= 3:
                        vm_source = parts[0]
                        vm_name = parts[1] 
                        vm_status = parts[-1]  # Last column is status
                        
                        vms.append({
                            "name": vm_name,
                            "status": vm_status,
                            "source": vm_source
                        })
            
            # Send response
            self.send_response(200)
            self.send_header('Content-Type', 'application/json')
            self.send_header('Access-Control-Allow-Origin', '*')
            self.end_headers()
            
            self.wfile.write(json.dumps(vms, indent=2).encode())
            
        except subprocess.TimeoutExpired:
            self.send_error(504, "Tart command timed out")
        except subprocess.CalledProcessError as e:
            self.send_error(500, f"Tart command failed: {e}")
        except Exception as e:
            self.send_error(500, f"Internal server error: {e}")
    
    def handle_vm_detail(self, vm_name):
        """Handle /vms/{name} endpoint"""
        try:
            # Get project root directory
            script_dir = os.path.dirname(os.path.abspath(__file__))
            project_root = os.path.dirname(script_dir)
            tart_bin = os.path.join(project_root, "tart-binary")
            
            # Run tart list command
            result = subprocess.run(
                [tart_bin, "list"],
                capture_output=True,
                text=True,
                timeout=10
            )
            
            vm_found = None
            if result.returncode == 0 and result.stdout.strip():
                # Parse tart list output to find the specific VM
                lines = result.stdout.strip().split('\n')
                for line in lines:
                    # Skip header line
                    if line.startswith('Source'):
                        continue
                    
                    parts = line.split()
                    if len(parts) >= 3:
                        vm_source = parts[0]
                        current_vm_name = parts[1] 
                        vm_status = parts[-1]  # Last column is status
                        
                        if current_vm_name == vm_name:
                            vm_found = {
                                "name": current_vm_name,
                                "status": vm_status,
                                "source": vm_source
                            }
                            break
            
            if vm_found:
                # Send success response
                self.send_response(200)
                self.send_header('Content-Type', 'application/json')
                self.send_header('Access-Control-Allow-Origin', '*')
                self.end_headers()
                
                self.wfile.write(json.dumps(vm_found, indent=2).encode())
            else:
                # VM not found
                self.send_error(404, f"VM '{vm_name}' not found")
            
        except subprocess.TimeoutExpired:
            self.send_error(504, "Tart command timed out")
        except subprocess.CalledProcessError as e:
            self.send_error(500, f"Tart command failed: {e}")
        except Exception as e:
            self.send_error(500, f"Internal server error: {e}")
    
    def handle_vm_start(self, vm_name):
        """Handle POST /vms/{name}/start endpoint"""
        try:
            # Get project root directory
            script_dir = os.path.dirname(os.path.abspath(__file__))
            project_root = os.path.dirname(script_dir)
            tart_bin = os.path.join(project_root, "tart-binary")
            
            # First check if VM exists
            list_result = subprocess.run(
                [tart_bin, "list"],
                capture_output=True,
                text=True,
                timeout=10
            )
            
            vm_exists = False
            if list_result.returncode == 0 and list_result.stdout.strip():
                lines = list_result.stdout.strip().split('\n')
                for line in lines:
                    if line.startswith('Source'):
                        continue
                    parts = line.split()
                    if len(parts) >= 2 and parts[1] == vm_name:
                        vm_exists = True
                        break
            
            if not vm_exists:
                self.send_error(404, f"VM '{vm_name}' not found")
                return
            
            # Start the VM in background (async)
            try:
                subprocess.Popen(
                    [tart_bin, "run", vm_name, "--no-audio", "--no-graphics"],
                    stdout=subprocess.DEVNULL,
                    stderr=subprocess.DEVNULL
                )
                response = {
                    "status": "success",
                    "message": f"VM '{vm_name}' start command issued",
                    "vm_name": vm_name,
                    "timestamp": datetime.now(timezone.utc).isoformat()
                }
                self.send_response(202)  # Accepted
            except Exception as e:
                response = {
                    "status": "error", 
                    "message": f"Failed to start VM '{vm_name}': {str(e)}",
                    "vm_name": vm_name,
                    "timestamp": datetime.now(timezone.utc).isoformat()
                }
                self.send_response(500)
            
            self.send_header('Content-Type', 'application/json')
            self.send_header('Access-Control-Allow-Origin', '*')
            self.end_headers()
            self.wfile.write(json.dumps(response, indent=2).encode())
            
        except subprocess.TimeoutExpired:
            self.send_error(504, "VM start command timed out")
        except Exception as e:
            self.send_error(500, f"Internal server error: {e}")
    
    def handle_vm_stop(self, vm_name):
        """Handle POST /vms/{name}/stop endpoint"""
        try:
            # Get project root directory
            script_dir = os.path.dirname(os.path.abspath(__file__))
            project_root = os.path.dirname(script_dir)
            tart_bin = os.path.join(project_root, "tart-binary")
            
            # First check if VM exists
            list_result = subprocess.run(
                [tart_bin, "list"],
                capture_output=True,
                text=True,
                timeout=10
            )
            
            vm_exists = False
            if list_result.returncode == 0 and list_result.stdout.strip():
                lines = list_result.stdout.strip().split('\n')
                for line in lines:
                    if line.startswith('Source'):
                        continue
                    parts = line.split()
                    if len(parts) >= 2 and parts[1] == vm_name:
                        vm_exists = True
                        break
            
            if not vm_exists:
                self.send_error(404, f"VM '{vm_name}' not found")
                return
            
            # Stop the VM
            stop_result = subprocess.run(
                [tart_bin, "stop", vm_name],
                capture_output=True,
                text=True,
                timeout=30
            )
            
            if stop_result.returncode == 0:
                response = {
                    "status": "success",
                    "message": f"VM '{vm_name}' stop command issued",
                    "vm_name": vm_name,
                    "timestamp": datetime.now(timezone.utc).isoformat()
                }
                self.send_response(200)
            else:
                response = {
                    "status": "error",
                    "message": f"Failed to stop VM '{vm_name}': {stop_result.stderr.strip()}",
                    "vm_name": vm_name,
                    "timestamp": datetime.now(timezone.utc).isoformat()
                }
                self.send_response(500)
            
            self.send_header('Content-Type', 'application/json')
            self.send_header('Access-Control-Allow-Origin', '*')
            self.end_headers()
            self.wfile.write(json.dumps(response, indent=2).encode())
            
        except subprocess.TimeoutExpired:
            self.send_error(504, "VM stop command timed out")
        except Exception as e:
            self.send_error(500, f"Internal server error: {e}")
    
    def log_message(self, format, *args):
        """Custom log format"""
        print(f"[{datetime.now().strftime('%Y-%m-%d %H:%M:%S')}] {format % args}")

def main():
    """Start the minimal VM API server"""
    port = 8082
    
    print(f"Starting Minimal VM API Server on port {port}")
    print(f"Health endpoint: http://localhost:{port}/health")
    print("Press Ctrl+C to stop")
    
    server = HTTPServer(('localhost', port), MinimalVMAPIHandler)
    
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\nShutting down server...")
        server.server_close()

if __name__ == "__main__":
    main()