#!/usr/bin/env python3
"""Call one civ6-mcp tool over MCP stdio and print its result as JSON."""

from __future__ import annotations

import argparse
import asyncio
import contextlib
import ctypes
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
    parser.add_argument(
        "--lock-timeout",
        type=float,
        default=120.0,
        help="seconds to wait for another local Civ MCP client to finish",
    )
    return parser.parse_args()


@contextlib.contextmanager
def single_client_lock(timeout: float):
    """Serialize local MCP clients because upstream binds dashboard port 8000."""
    if os.name != "nt":
        yield
        return

    kernel32 = ctypes.WinDLL("kernel32", use_last_error=True)
    kernel32.CreateMutexW.argtypes = [ctypes.c_void_p, ctypes.c_bool, ctypes.c_wchar_p]
    kernel32.CreateMutexW.restype = ctypes.c_void_p
    kernel32.WaitForSingleObject.argtypes = [ctypes.c_void_p, ctypes.c_uint32]
    kernel32.WaitForSingleObject.restype = ctypes.c_uint32
    kernel32.ReleaseMutex.argtypes = [ctypes.c_void_p]
    kernel32.ReleaseMutex.restype = ctypes.c_bool
    kernel32.CloseHandle.argtypes = [ctypes.c_void_p]
    kernel32.CloseHandle.restype = ctypes.c_bool

    handle = kernel32.CreateMutexW(None, False, "Local\\Civ6DesyncLabMcpClient")
    if not handle:
        raise OSError(ctypes.get_last_error(), "CreateMutexW failed")

    wait_ms = max(0, min(round(timeout * 1000), 0xFFFFFFFE))
    acquired = False
    try:
        result = kernel32.WaitForSingleObject(handle, wait_ms)
        if result not in (0x00000000, 0x00000080):
            if result == 0x00000102:
                raise TimeoutError(
                    f"another Civ MCP client did not finish within {timeout:g} seconds"
                )
            raise OSError(ctypes.get_last_error(), f"WaitForSingleObject failed: {result:#x}")
        acquired = True
        yield
    finally:
        if acquired:
            kernel32.ReleaseMutex(handle)
        kernel32.CloseHandle(handle)


async def main(args: argparse.Namespace) -> None:
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
    parsed_args = parse_args()
    with single_client_lock(parsed_args.lock_timeout):
        asyncio.run(main(parsed_args))
