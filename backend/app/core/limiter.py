import os
import sys
from slowapi import Limiter
from slowapi.util import get_remote_address

# Global rate limiter using remote address as key.
# Disable rate limiting automatically in test runs to prevent 429s.
is_testing = (
    "pytest" in sys.modules
    or any("pytest" in arg for arg in sys.argv)
    or os.environ.get("TESTING") == "true"
)
limiter = Limiter(key_func=get_remote_address, enabled=not is_testing)


