#!/usr/bin/env python3
"""Raise the debugger-region cap to 2 GiB, honor the executor-cache-budget
env vars in prepare_jit_memory, and document the Runtime.mm / net-probe
hooks. Run from the Kernarium tree after 0018. Idempotent for the two
C++ files; Runtime.mm and GuestSessionTests.swift are described in the
README if the automatic hooks cannot be applied."""
from pathlib import Path
import sys

em = Path("darwin/cpu/jit_memory/executable_memory.cpp")
ctx = Path("darwin/runtime/context.cpp")
if not em.is_file() or not ctx.is_file():
    sys.exit("run from the Kernarium tree")

t = em.read_text()
old = "constexpr std::size_t region_limit = 1024U * 1024U * 1024U;"
new = "constexpr std::size_t region_limit = 2U * 1024U * 1024U * 1024U;"
if new in t:
    print("executable_memory.cpp already has a 2 GiB region_limit")
elif old in t:
    em.write_text(t.replace(old, new, 1))
    print("patched executable_memory.cpp region_limit")
else:
    sys.exit("executable_memory.cpp: unexpected region_limit")

t = ctx.read_text()
if "jit_executor_cache_budget_for" in t:
    print("context.cpp already has jit_executor_cache_budget_for")
else:
    needle = """#ifndef UML_APP_STORE_RUNTIME
std::size_t jit_cache_budget_for(std::size_t guest_memory_bytes,
	unsigned executors) noexcept
{
"""
    helper = """#ifndef UML_APP_STORE_RUNTIME
std::size_t jit_executor_cache_budget_for(std::size_t fallback) noexcept
{
	constexpr std::size_t cap = 256U * 1024U * 1024U;
	for (const char *name :
		{"KERNARIUM_JIT_EXECUTOR_CACHE_BUDGET",
		 "UML_JIT_EXECUTOR_CACHE_BUDGET"}) {
		if (const char *text = std::getenv(name)) {
			const auto parsed =
				parse_translation_cache_quantity(text);
			if (parsed != 0 && parsed <= cap)
				return parsed;
		}
	}
	return fallback != 0 ? fallback : cap;
}

std::size_t jit_cache_budget_for(std::size_t guest_memory_bytes,
	unsigned executors) noexcept
{
"""
    if needle not in t:
        sys.exit("context.cpp: unexpected jit_cache_budget_for")
    t = t.replace(needle, helper, 1)
    old = """	return ::uml::cpu::prepare_jit_memory(
		jit_cache_budget_for(guest_memory_bytes, executors), executors,
		per_executor_bytes);
"""
    newp = """	return ::uml::cpu::prepare_jit_memory(
		jit_cache_budget_for(guest_memory_bytes, executors), executors,
		jit_executor_cache_budget_for(per_executor_bytes));
"""
    if old not in t:
        sys.exit("context.cpp: unexpected prepare_jit_memory body")
    ctx.write_text(t.replace(old, newp, 1))
    print("patched context.cpp")
