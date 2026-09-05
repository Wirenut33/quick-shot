"""Deterministic, increasing versions from main's Git ancestry, including reruns."""
import re
import subprocess


def versions(revision_count: int, major_minor: str = "1.4") -> tuple[str, str]:
    if revision_count < 1 or not re.fullmatch(r"\d+\.\d+", major_minor):
        raise ValueError("Expected a positive revision count and major.minor version")
    return f"{major_minor}.{revision_count}", str(1000 + revision_count)


if __name__ == "__main__":
    count = int(subprocess.check_output(["git", "rev-list", "--count", "HEAD"], text=True))
    version, build = versions(count)
    print(f"version={version}")
    print(f"build={build}")
    print(f"tag=v{version}")
