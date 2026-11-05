# One entry point per pipeline.
#
# Command contracts, prerequisites and CI mapping: PIPELINES.md.

.PHONY: help backend frontend library release coverage check

help: ## Lista os alvos; contratos em PIPELINES.md
	@echo "Alvos: backend frontend library release coverage check"
	@echo "Quando usar, pré-requisitos e efeitos: PIPELINES.md"

backend: ## Gates do backend e scan de segurança
	MIX_ENV=test mix gate
	MIX_ENV=test mix sobelow --exit

frontend: ## Pipeline de assets: checks, instala ferramentas, compila e digere
	bash scripts/check_assets.sh
	MIX_ENV=dev mix assets.setup
	MIX_ENV=dev mix assets.build
	MIX_ENV=dev mix assets.deploy

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
