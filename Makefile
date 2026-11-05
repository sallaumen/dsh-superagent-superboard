# One entry point per pipeline.
#
# Command contracts, prerequisites and CI mapping: PIPELINES.md.

.PHONY: help backend frontend library release coverage check

help: ## Lista os pipelines e quando usar cada um
	@echo "backend   — gates do Elixir e scan Sobelow (sem corrigir fontes). Use antes de abrir PR."
	@echo "frontend  — build e deploy de assets (esbuild + tailwind). Use ao mudar CSS/JS."
	@echo "library   — validador e testes da biblioteca de capacidades. Use ao mudar capabilities/."
	@echo "release   — caminho misto de deploy (assets dev + compile/digest/release prod). Lento; use antes de deploy."
	@echo "coverage  — relatório de cobertura da suíte (HTML em cover/). Sai com erro se < 90% (threshold padrão do Elixir); o HTML é gerado mesmo assim."
	@echo "check     — os três pipelines separados juntos. Use antes de entregar qualquer PR."

backend: ## Gates do backend e scan de segurança
	mix gate
	MIX_ENV=test mix sobelow --exit

frontend: ## Pipeline de assets: checks, instala ferramentas, compila e digere
	bash scripts/check_assets.sh
	mix assets.setup
	mix assets.build
	mix assets.deploy

library: ## Integridade da biblioteca de capacidades (somente leitura)
	python3 capabilities/tools/validar_biblioteca.py
	python3 capabilities/tools/test_validar_biblioteca.py

release: ## Pipeline misto: assets em dev; compile, digest e release em prod
	MIX_ENV=dev mix assets.setup
	MIX_ENV=dev mix assets.build
	MIX_ENV=prod mix compile --warnings-as-errors
	MIX_ENV=prod mix phx.digest
	MIX_ENV=prod mix release --overwrite

coverage: ## Relatório de cobertura da suíte (HTML em cover/, ignorado pelo git)
	MIX_ENV=test mix test --cover
check: backend frontend library ## Os pipelines de PR; release é separado
