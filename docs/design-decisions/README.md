# Design decisions

Written rationale for the major technical choices in ShreeOS. Each decision is
recorded in the document that owns it, so this page is an index rather than a
second copy of the reasoning.

| Decision | Where the rationale lives |
|---|---|
| Build pipeline, target platform, and why the source-built stack exists at all | [`../ARCHITECTURE.md`](../ARCHITECTURE.md) |
| Why the release product is one Debian 13 + KDE Plasma image | [`../UNIFIED-ARCHITECTURE.md`](../UNIFIED-ARCHITECTURE.md) |
| What is integrated into the image, and what is deliberately excluded | [`../UNIFIED-ARCHITECTURE.md`](../UNIFIED-ARCHITECTURE.md) |
| Which native ShreeOS components are wired into the desktop | [`../COMPONENT_INTEGRATION_MATRIX.md`](../COMPONENT_INTEGRATION_MATRIX.md) |
| Why KDE Plasma is the desktop and how it is configured | [`../KDE-PLASMA-INTEGRATION.md`](../KDE-PLASMA-INTEGRATION.md) |
| How the unified desktop image is built and gated | [`../UNIFIED-IMAGE.md`](../UNIFIED-IMAGE.md) |
| Visual language, colour, and branding rules | [`../../branding/DESIGN_SYSTEM.md`](../../branding/DESIGN_SYSTEM.md) |
| Third-party components and their licences | [`../OPEN_SOURCE_COMPONENTS.md`](../OPEN_SOURCE_COMPONENTS.md), [`../../THIRD_PARTY_LICENSES.md`](../../THIRD_PARTY_LICENSES.md) |
| Where upstream code and versions come from | [`../UPSTREAM_CODE.md`](../UPSTREAM_CODE.md) |
| Milestone plan and the rules for changing scope | [`../ROADMAP.md`](../ROADMAP.md) |

The dated audits under [`../audit/`](../audit/) record what was true of the
tree at a specific commit. They are history, not current product inventory.
