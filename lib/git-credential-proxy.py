#!/usr/bin/env python3
"""
Git Credential Proxy for macOS Keychain

This service runs on the macOS host and proxies git credential requests
from Docker containers to the macOS keychain via git-credential-osxkeychain.

Protocol:
- Listens on a Unix socket
- Receives git credential protocol messages (get/store/erase)
- Forwards to git-credential-osxkeychain
- Returns responses back to the client

Usage:
    python3 git-credential-proxy.py [socket_path]
"""

import os
import sys
import socket
import subprocess
import signal
import logging
from pathlib import Path

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger('git-credential-proxy')

# Default socket path
DEFAULT_SOCKET_PATH = '/tmp/git-credential-proxy.sock'

# Path to macOS git credential helper
# Use git's credential-osxkeychain subcommand
GIT_CREDENTIAL_HELPER = ['git', 'credential-osxkeychain']


class GitCredentialProxy:
    def __init__(self, socket_path):
        self.socket_path = socket_path
        self.server_socket = None
        self.running = False
        
    def cleanup_socket(self):
        """Remove existing socket file if it exists"""
        if os.path.exists(self.socket_path):
            try:
                os.unlink(self.socket_path)
                logger.info(f"Removed existing socket: {self.socket_path}")
            except OSError as e:
                logger.error(f"Failed to remove socket: {e}")
                raise
    
    def handle_credential_request(self, client_socket):
        """Handle a single credential request from a client"""
        try:
            # Read the request from the client
            # Git credential protocol sends key=value pairs terminated by blank line
            request_data = b''
            while True:
                chunk = client_socket.recv(4096)
                if not chunk:
                    break
                request_data += chunk
                # Check if we have a complete request (ends with \n\n)
                if b'\n\n' in request_data or b'\r\n\r\n' in request_data:
                    break
            
            if not request_data:
                logger.debug("Empty request received")
                return
            
            request_str = request_data.decode('utf-8')
            logger.debug(f"Received request:\n{request_str}")
            
            # Parse operation from first line
            lines = request_str.split('\n', 1)
            if len(lines) < 2:
                logger.error("Invalid request format: missing operation")
                return
            
            operation = lines[0].strip()
            credential_data = lines[1] if len(lines) > 1 else ''
            
            if operation not in ['get', 'store', 'erase']:
                logger.error(f"Invalid operation: {operation}")
                return
            
            logger.debug(f"Operation: {operation}")
            
            # Forward to git-credential-osxkeychain
            process = None
            try:
                cmd = GIT_CREDENTIAL_HELPER + [operation]
                process = subprocess.Popen(
                    cmd,
                    stdin=subprocess.PIPE,
                    stdout=subprocess.PIPE,
                    stderr=subprocess.PIPE
                )
                
                stdout, stderr = process.communicate(input=credential_data.encode('utf-8'), timeout=30)
                
                if stderr:
                    logger.warning(f"Credential helper stderr: {stderr.decode('utf-8')}")
                
                # Send response back to client
                if stdout:
                    client_socket.sendall(stdout)
                    logger.debug(f"Sent response ({len(stdout)} bytes)")
                else:
                    logger.debug("No response from credential helper")
                    
            except subprocess.TimeoutExpired:
                logger.error("Credential helper timed out")
                if process:
                    process.kill()
            except FileNotFoundError:
                logger.error(f"Credential helper not found: {GIT_CREDENTIAL_HELPER}")
            except Exception as e:
                logger.error(f"Error calling credential helper: {e}")
                
        except Exception as e:
            logger.error(f"Error handling request: {e}")
        finally:
            try:
                client_socket.close()
            except:
                pass
    
    def start(self):
        """Start the proxy server"""
        # Clean up any existing socket
        self.cleanup_socket()
        
        # Create Unix socket
        self.server_socket = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        self.server_socket.bind(self.socket_path)
        self.server_socket.listen(5)
        
        # Make socket accessible
        os.chmod(self.socket_path, 0o666)
        
        logger.info(f"Git credential proxy listening on {self.socket_path}")
        logger.info(f"Using credential helper: {GIT_CREDENTIAL_HELPER}")
        
        self.running = True
        
        # Accept connections
        while self.running:
            try:
                client_socket, _ = self.server_socket.accept()
                logger.debug("Client connected")
                self.handle_credential_request(client_socket)
            except KeyboardInterrupt:
                logger.info("Received interrupt signal")
                break
            except Exception as e:
                if self.running:
                    logger.error(f"Error accepting connection: {e}")
        
        self.stop()
    
    def stop(self):
        """Stop the proxy server"""
        logger.info("Stopping git credential proxy")
        self.running = False
        
        if self.server_socket:
            try:
                self.server_socket.close()
            except:
                pass
        
        self.cleanup_socket()


def signal_handler(signum, frame):
    """Handle shutdown signals"""
    logger.info(f"Received signal {signum}")
    sys.exit(0)


def main():
    # Set up signal handlers
    signal.signal(signal.SIGINT, signal_handler)
    signal.signal(signal.SIGTERM, signal_handler)
    
    # Get socket path from command line or use default
    socket_path = sys.argv[1] if len(sys.argv) > 1 else DEFAULT_SOCKET_PATH
    
    # Create and start proxy
    proxy = GitCredentialProxy(socket_path)
    
    try:
        proxy.start()
    except Exception as e:
        logger.error(f"Fatal error: {e}")
        sys.exit(1)


if __name__ == '__main__':
    main()
