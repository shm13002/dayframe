# Vendored Hermes gateway client

These four files are copied unchanged from Nous Research's Hermes Agent (MIT, see `LICENSE`):
`apps/shared/src/{json-rpc-gateway,json-rpc-channel,gateway-events,gateway-contract.generated}.ts`
at commit `300228d24c593f779055204753921fbe9a2163c5` (2026-10-14), the revision installed in
`~/.hermes/hermes-agent`. Herald OS (MIT) consumes the same files the same way.

To update: copy the four files from the installed Hermes (`hermes update` first), change the sha above,
then run `npm run check`. Don't edit them by hand; they are excluded from Prettier.
