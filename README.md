# cross-rollup-bridge

This hack was developed for the ETHGlobal Scaling Ethereum hackathon, to demonstrate cross-rollup transactions at O(1) L1 gas cost.

It currently supports Arbitrum and Optimism, but can be easily extended to support any rollup.

The idea is to use L1 as a shared source of truth, syncing merkle roots across rollups to pass messages or create a shared state object.

Messages are added to the tree on one side, and redeemed on the other side using proofs.

For simplicity, the current implementation uses an L1 helper contract that passes merkle roots between rollup bridges.  Future implementation will not require sending anything from L2 to L1.  It will just push L1 block hashes to the rollups, and the L2 contracts will support proving L1 state against the L1 block hashes.  The proven L1 state will actually be the latest finalized state root of another rollup, and the contracts will allow proving states across L2 directly.

Rollups could make this more efficient and remove the need for any L1 component by adding a precompile that exposes L1 block hashes to L2 contracts.  In the case of optimistic rollups these L1 block hashes should be a part of the state commitment and will be covered by the fraud prover.  This change eliminates the need for any L1 component and allows direct access to cross rollup state.

An improved version of this precompile could eliminate the need for merkle proofs against the L1 block hashes.  The precompile could instead offer access to the state of any L1 contract.  The sequencer will act as a state oracle, providing L1 state when requested by L2 contracts without needing a merkle proof on L2.  The accessed L1 storage cells will become part of the rollup batch so they'll be subject to fraud proofs.

The obvious caveat when accessing cross-rollup state, is that it may not be current.  Therefore it should only be used with state that can no longer change on the other rollup.  For example, an ERC20 token would burn tokens on one side, and then the other side can safely mint them after verifying the burn proof.  This repo includes an ERC20 contract that does just that:

- `ERC20.sendToOtherChain(uint256 _amount)` - burn the amount on the sending rollup and add a message to the bridge, to mint them on the other rollup.
- `ERC20.receiveFromOtherChain(uint256 nonce, address to, uint256 amount, bytes32 rootHash, uint256 branchMask, bytes32[] memory siblings)` - mint the received tokens on the other rollup by proving the message. A message can only be redeemed once.
- `ERC20.getProof(uint256 _nonce, address from, uint256 amount)` - get a proof which can be used by `receiveFromOtherChain`.

After sending any number of messages, `L2MessageBridge.updateL2Bridges([chainIDs])` should be called.  It syncs the merkle root of the accuulated messages to the specified chain IDs.  E.g. if used by Optimism on kovan (69) to send tokens to Arbitrum on kovan (212984383488152), `L2MessageBridge.updateL2Bridges([212984383488152])` should be called on Optimism to send the messages to the Arbitrum side.

Using the bridge directly:

- `L2MessageBridge.send(address to, bytes memory message, uint256 toChainId)` - queue an arbitrary message to address `to` on chain `toChainId`.
- `L2MessageBridge.getMessageProof(uint256 nonce, address from, address to, uint256 fromChainId, uint256 toChainId, bytes memory message)` - get a proof against the current root.  Proofs should be requested only after the root exists on the other side because they will become invalid if root changes before it is synced.  A proof for a past message can be generated at any time against the current root.
- `L2MessageBridge.verify(uint256 nonce, address from, address to, uint256 fromChainId, uint256 toChainId, bytes memory message, bytes32 rootHash, uint branchMask, bytes32[] memory siblings)` - verify a proof from any chain.
- `L2MessageBridge.redeem(uint256 nonce, address from, uint256 fromChainId, bytes memory message, bytes32 rootHash, uint branchMask, bytes32[] memory siblings)` - redeem a message from another chain.  Upon success the message is invalidated.
- `L2MessageBridge.updateL1Bridge()` - update the L1 helper bridge with the latest root.  Will be removed when the need for L1 help is eliminated.
- `L2MessageBridge.updateL2Bridges(uint256[] memory toChainIDs)` - updates the L1 bridge and trigger a root sync to a list of chains.  Will be removed when the need for L1 help is eliminated.

Note on Brownie: This project uses Brownie scripts. Unfortunately I found out that it's not trivial to use Optimism's solcjs fork with Brownie.  I made it work but still need to clean it up before submitting pull requests to eth-brownie and to py-solc-x.

## Bugs encountered during development

- Arbitrum - the transaction receipts for L1->L2 messages (retryable tickets) shows the wrong destination address.  This confuses scripts, and the explorer also provides bogus data for such transactions.  The actual transaction is correct - only the receipt is bad.  Reported to Arbitrum.
- Optimism - batch submitter and message relayer have been unstable, making message delivery unreliable.  Reported to Optimism.
- Brownie (and solcx which it uses) had multiple problems working with OVM:
  - No support for solcjs, only solc.  Incompatible arguments, etc.  Fixed with a wrapper.
  - Long json output is truncted because solcx uses python's subprocess.Popen().communicate() which is limited to max pipe block size (64k) and does't support multiple reads.  OVM compilations tend to be larger and hit that limit.  Fixed by replacing the pipe with a temporary file.  PR to follow.
  - Brownie makes it difficult to hold concurrent connections to multiple chains in the same process due to using module-wide globals.  Not fixed.  Requires a design change.  As a workaround I used a separate process for each chain.
