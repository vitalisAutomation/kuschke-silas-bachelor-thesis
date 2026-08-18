#!/usr/bin/env python3
# SPDX-FileCopyrightText: Bosch Rexroth AG
#
# SPDX-License-Identifier: MIT

import sys
import time
import logging
import numpy as np

# Konfiguriere das Logging direkt für stdout (Kanal 1)
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
    datefmt="%Y-%m-%d %H:%M:%S",
    stream=sys.stdout
)
logger = logging.getLogger("sdk-py-console")

def main():
    """Run a minimal NumPy calculation and log the result repeatedly."""
    logger.info("NumPy Console Daemon started...")
    
    while True:
        # Eine saubere NumPy-Berechnung ohne störende Platzhalter
        matrix = np.array([[1, 2], [3, 4]])
        result = int(np.sum(matrix @ matrix))
        
        logger.info("--- NumPy Cross-Compile Test ---")
        logger.info("A = [[1, 2], [3, 4]]")
        logger.info(f"sum(A @ A) = {result}")
        
        # 5 Sekunden warten vor der nächsten Berechnung
        time.sleep(5.0)

if __name__ == "__main__":
    main()
