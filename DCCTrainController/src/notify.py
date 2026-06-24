"""
macOS system notifications via osascript — no extra dependencies.
Sends a banner notification to Notification Center.
"""

import subprocess
import logging

logger = logging.getLogger(__name__)


def notify(title: str, message: str):
    """Post a macOS Notification Center banner."""
    script = (
        f'display notification "{message}" '
        f'with title "Train Controller" '
        f'subtitle "{title}"'
    )
    try:
        subprocess.run(
            ["osascript", "-e", script],
            capture_output=True,
            timeout=3,
        )
    except Exception as e:
        logger.debug("Notification failed: %s", e)
