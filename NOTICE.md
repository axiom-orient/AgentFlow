# Source and scope

AgentFlow is the standalone runtime extracted from the original AgentFlow
component previously maintained inside MoToolbox. On 2026-10-27 its copyright
holder authorized publication of this component under MIT.

This permission and the MIT license apply to the runtime and accompanying
material in this repository. They do not relicense MoToolbox's host tools,
private distribution, third-party components, or any consuming application's
source, assets, configuration, records, or models.

The initial extraction preserves the runtime's public API and behavior. The
package deployment targets are iOS 17 and macOS 14. No TCA, reactive framework,
architecture macro, host CLI, database, network provider, or application model
is included. External architecture implementations were researched as design
references; their source was not copied into this runtime.
