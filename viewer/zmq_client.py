"""
ZMQ Client for EPH Simulation
Subscribes to global and detail packets
"""

import zmq
import msgpack
import numpy as np
from typing import Optional, Dict, Any


class ZMQClient:
    """ZMQ SUB client for receiving simulation data"""
    
    def __init__(self, endpoint: str = "tcp://127.0.0.1:5555", timeout_ms: int = 100):
        """
        Initialize ZMQ subscriber
        
        Args:
            endpoint: ZMQ endpoint to connect to
            timeout_ms: Receive timeout in milliseconds
        """
        self.context = zmq.Context()
        self.socket = self.context.socket(zmq.SUB)
        self.socket.connect(endpoint)
        self.socket.setsockopt(zmq.RCVTIMEO, timeout_ms)
        
        print(f"📡 ZMQ Client connected to {endpoint}")
    
    def subscribe(self, topic: str):
        """Subscribe to a topic"""
        self.socket.subscribe(topic.encode())
        print(f"   Subscribed to topic: '{topic}'")
    
    def receive(self) -> Optional[tuple[str, Dict[str, Any]]]:
        """
        Receive message (non-blocking)
        
        Returns:
            (topic, data) tuple or None if timeout
        """
        try:
            # Drain queue to get the latest message (manual conflate)
            latest_msg = None
            while True:
                try:
                    # Non-blocking receive for draining
                    latest_msg = self.socket.recv_multipart(flags=zmq.NOBLOCK)
                except zmq.Again:
                    break
            
            # If no message found in queue, try blocking receive (with timeout) 
            # only if we haven't received anything yet?
            # Actually, main loop calls this periodically. 
            # If we rely on NOBLOCK, we might return None often.
            # But update() is 30fps.
            
            if latest_msg is None:
                # If queue was empty, try one blocking receive to wait for data (sync)
                # But since we want to avoid lag, maybe just return None if empty?
                # If we return None, viewer shows old frame. That's fine.
                try:
                    latest_msg = self.socket.recv_multipart()
                except zmq.Again:
                    return None

            # Process the message
            if len(latest_msg) < 2:
                return None
                
            topic_bytes = latest_msg[0]
            data_bytes = latest_msg[1]
            
            # Decode
            topic = topic_bytes.decode().strip()
            data = msgpack.unpackb(data_bytes, raw=False)
            
            # Convert lists to numpy arrays for convenience
            if "positions" in data:
                data["positions"] = [np.array(p) for p in data["positions"]]
            if "velocities" in data:
                data["velocities"] = [np.array(v) for v in data["velocities"]]
            if "position" in data:
                data["position"] = np.array(data["position"])
            if "velocity" in data:
                data["velocity"] = np.array(data["velocity"])
            if "action" in data:
                data["action"] = np.array(data["action"])
            if "spm" in data:
                # MsgPack flattens multidimensional arrays
                # Reshape from 1D to (16, 16, 3)
                spm_flat = np.array(data["spm"])
                if spm_flat.ndim == 1:
                    # Assume shape is (16, 16, 3) = 768 elements
                    data["spm"] = spm_flat.reshape((16, 16, 3))
                else:
                    data["spm"] = spm_flat
            
            return topic, data
            
        except zmq.Again:
            # Timeout
            return None
        except Exception as e:
            print(f"⚠️  ZMQ receive error: {e}")
            return None
    
    def close(self):
        """Close connection"""
        self.socket.close()
        self.context.term()
        print("📡 ZMQ Client closed")


if __name__ == "__main__":
    # Test client
    client = ZMQClient()
    client.subscribe("global")
    client.subscribe("detail")
    
    print("\n🔄 Listening for messages (Ctrl+C to stop)...\n")
    
    try:
        while True:
            msg = client.receive()
            if msg:
                topic, data = msg
                print(f"[{topic}] Step {data.get('step', '?')}")
    except KeyboardInterrupt:
        print("\n⏸️  Stopped")
    finally:
        client.close()
