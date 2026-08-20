#!/usr/bin/env python3
"""Call one civ6-mcp tool over MCP stdio and print its result as JSON."""

from __future__ import annotations

import argparse
import asyncio
import json
import os
import sys
from pathlib import Path

from mcp import ClientSession, StdioServerParameters
from mcp.client.stdio import stdio_client


def parse_args() -> argparse.Namespace:
    default_runtime = Path(os.environ.get("LOCALAPPDATA", "")) / "Civ6DesyncLab" / "civ6-mcp"
    parser = argparse.ArgumentParser()
    parser.add_argument("tool", nargs="?", help="MCP tool name")
    parser.add_argument("--args", default="{}", help="Tool arguments as a JSON object")
    parser.add_argument("--list-tools", action="store_true")
    parser.add_argument("--runtime", type=Path, default=default_runtime)
    return parser.parse_args()


async def main() -> None:
    args = parse_args()
    runtime = args.runtime.resolve()
    if not runtime.is_dir():
        raise SystemExit(f"civ6-mcp runtime does not exist: {runtime}")

    parameters = StdioServerParameters(
        command=sys.executable,
        args=["-m", "civ_mcp"],
        cwd=str(runtime),
    )
    async with stdio_client(parameters) as (reader, writer):
        async with ClientSession(reader, writer) as session:
            await session.initialize()
            if args.list_tools:
                result = await session.list_tools()
                print(json.dumps([tool.model_dump() for tool in result.tools], indent=2))
                return
            if not args.tool:
                raise SystemExit("provide TOOL or use --list-tools")
            arguments = json.loads(args.args)
            if not isinstance(arguments, dict):
                raise SystemExit("--args must decode to a JSON object")
            result = await session.call_tool(args.tool, arguments)
            print(result.model_dump_json(indent=2))


if __name__ == "__main__":
    asyncio.run(main())
