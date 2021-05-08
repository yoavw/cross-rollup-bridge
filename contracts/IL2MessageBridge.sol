pragma solidity >=0.5.0 <0.8.0;

interface IL2MessageBridge {

	event MessageStored(uint256 nonce, address from, address to, uint256 fromChainId, uint256 toChainId, bytes message);
	event SentRoot(bytes32 indexed root);
	event ReceivedRoot(bytes32 indexed root, uint256 indexed chainID);
	event Redeemed(bytes32 key);
	event ArbitrumToL1TxCreated(uint256 withdrawalId);

	function send(address to, bytes memory message, uint256 toChainId) external returns (uint256 nonce);
	function redeem(uint256 nonce, address from, uint256 fromChainId, bytes memory message, bytes32 rootHash, uint branchMask, bytes32[] memory siblings) external;
	function getChainID() external view returns (uint256);
	function getMessageProof(uint256 nonce, address from, address to, uint256 fromChainId, uint256 toChainId, bytes memory message) external view returns (bytes32 rootHash, uint branchMask, bytes32[] memory siblings);
}

