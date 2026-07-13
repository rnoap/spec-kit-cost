# spec-kit-cost

<!-- WIBEY-GRAPH-PRIORITY START -->
## ⚠️ CRITICAL: Codebase Exploration

**ALWAYS explore the codebase with the code-review-graph MCP tools BEFORE `grep_search` / `file_search` / `read_file`.**

```
✅ mcp_code-review-g_semantic_search_nodes_tool  (provider=local, model=all-MiniLM-L6-v2)
✅ mcp_code-review-g_query_graph_tool            (callers / callees / imports / tests)
❌ grep_search as a first step to find a file, class, function or module
```

Before any `grep_search`, ask: "Could the knowledge graph answer this?" If yes, use the graph first. `grep_search` is only for exact literal strings the graph doesn't index. See the "code-review-graph MCP" section below for full details.

> If `code-review-graph` is not yet installed, run `/speckit-setup` first.
<!-- WIBEY-GRAPH-PRIORITY END -->

> Wibey/AI project context file (authoritative).

## Project

**Name:** spec-kit-cost  
**Purpose:** _Add a short description of this project here._

## Spec-Driven Development

This project uses [spec-kit](https://gecgithub01.walmart.com/developer-solutions/spec-kit) for spec-driven development.

- Specifications live in `specs/`
- Each feature gets its own `specs/<NNN>-<name>/` directory containing `spec.md`, `plan.md`, and `tasks.md`
- Use `/spec-kit-walmart:spec-architect` to create new specs or get help with the SDD workflow
