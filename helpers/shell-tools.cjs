'use strict';
/**
 * The shell tools, ONE list (2026-11-24, measured on the macOS instance at the train head 72c6663): ten core gates read
 * a shell command only when the tool was `Bash`, so on Windows - where the main shell is the PowerShell tool - a
 * background run, a search, a diff read or an own failure went unseen. A gate that must read only Bash says so at
 * its site; every other one asks here.
 */
const SHELL_TOOLS = new Set(['Bash', 'PowerShell']);
const isShell = (name) => SHELL_TOOLS.has(name);
module.exports = { SHELL_TOOLS, isShell };
