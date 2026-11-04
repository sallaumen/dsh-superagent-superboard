# One entry point per pipeline.
#
# Each target maps 1:1 to a CI job of .github/workflows/ci.yml, so "what CI
# runs" and "what you can run locally" never drift. Prerequisites:
#   - Elixir/OTP on PATH (backend, frontend)
#   - a local Postgres at 127.0.0.1:5434 with user/password "board"
#     (the test alias creates the databases itself)
#   - Python 3.10+ on PATH (library)
#
# This layout is generic: a project of any stack can mirror it by giving each
# pipeline its own target with a documented contract (inputs, effects, when
# to use). See PIPELINES.md.

.PHONY: help backend frontend library check

help: ## Lista os pipelines e quando usar cada um
	@echo "backend   — gates do Elixir (gate check-only). Use antes de abrir PR."
	@echo "frontend  — build e deploy de assets (esbuild + tailwind). Use ao mudar CSS/JS."
	@echo "library   — validador e testes da biblioteca de capacidades. Use ao mudar capabilities/."
	@echo "check     — os três pipelines juntos. Use antes de entregar qualquer PR."

backend: ## Gates do backend: compile sem warnings + format check + credo + testes
	mix gate

frontend: ## Pipeline de assets: instala ferramentas, compila e digere
	mix assets.setup
	mix assets.build
	mix assets.deploy

library: ## Integridade da biblioteca de capacidades (somente leitura)
	python3 capabilities/tools/validar_biblioteca.py
	python3 capabilities/tools/test_validar_biblioteca.py

check: backend frontend library ## Todos os pipelines (o mesmo conjunto da CI)
