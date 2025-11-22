import time
from src.core.environment import Environment

class Simulator:
    def __init__(self, environment: Environment):
        self.environment = environment
        self.running = False

    def step(self):
        # 1. Sense & Decide
        for agent in self.environment.agents:
            agent.sense(self.environment)
            agent.decide_action(self.environment)
            
        # 2. Update Physics
        self.environment.update()

    def run(self, duration=None):
        """
        Run simulation for a specific duration (seconds) or indefinitely if None.
        This is a blocking call if used without a GUI loop.
        """
        self.running = True
        start_time = time.time()
        
        while self.running:
            current_time = time.time()
            if duration and (current_time - start_time > duration):
                self.running = False
                break
            
            self.step()
            time.sleep(self.environment.dt) # Simple sleep to match real-time roughly
