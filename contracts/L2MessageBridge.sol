pragma solidity >=0.5.0 <0.8.0;

import "./tree/Patricia.sol";
import "./arbitrum/Arbsys.sol";
import "./L1RootBridge.sol";
import "./optimism/OVM_CrossDomainEnabled.sol";
import "./optimism/Lib_AddressResolver.sol";

contract L2MessageBridge is PatriciaTree, OVM_CrossDomainEnabled, Lib_AddressResolver {

	event MessageStored(uint256 nonce, address from, address to, uint256 fromChainId, uint256 toChainId, bytes message);
	event SentRoot(bytes32 indexed root);
	event ReceivedRoot(bytes32 indexed root, uint256 indexed chainID);
	event Redeemed(bytes32 key);
	event ArbitrumToL1TxCreated(uint256 withdrawalId);
	event Debug(bytes32 b);
	event Debug(address a);

	uint256 public currentNonce;
	mapping (bytes32 => bool) public remoteRoots;
	mapping (bytes32 => bool) public redeemed;
	L1RootBridge public l1RootBridge;
	uint32 public bridgeType;	// 0 - Test  1 - Arbitrum   2 - Optimism ...

	ArbSys constant arbsys = ArbSys(100);
	bytes32 constant arbsysCodeHash = 0xbcc90f2d6dada5b18e155c17a1c0a55920aae94f39857d39d0d8ed07ae8f228b;

	

	constructor(L1RootBridge _l1RootBridge) public
		OVM_CrossDomainEnabled(address(0)) // overridden in constructor code
		Lib_AddressResolver(address(0x4200000000000000000000000000000000000008))
	{
		l1RootBridge = _l1RootBridge;
		bytes32 codeHash;	
		assembly { codeHash := extcodehash(100) }
		if (codeHash == arbsysCodeHash) {
			bridgeType = 1;
			return;
		}
		assembly { codeHash := extcodehash(0x4200000000000000000000000000000000000000) }
		if (codeHash != 0) {
			messenger = resolve("OVM_L2CrossDomainMessenger");
			require(messenger != address(0), "Unable to find Optimism messenger");
			bridgeType = 2;
			return;
		}
	}

	function send(address to, bytes memory message, uint256 toChainId) public returns (uint256 nonce) {
		nonce = currentNonce;
		bytes32 key = getKey(nonce, msg.sender, to, getChainID(), toChainId, message);
		currentNonce++;
		insert(abi.encode(key), message);
		emit MessageStored(nonce, msg.sender, to, getChainID(), toChainId, message);
		return nonce;
	}

	function getKey(uint256 nonce, address from, address to, uint256 fromChainId, uint256 toChainId, bytes memory message) public pure returns (bytes32 key) {
		return keccak256(abi.encode(nonce,from,to,fromChainId,toChainId,message));
	}

	function verify(uint256 nonce, address from, address to, uint256 fromChainId, uint256 toChainId, bytes memory message, bytes32 rootHash, uint branchMask, bytes32[] memory siblings) public pure returns (bytes32 key) {
		bytes32 _key = getKey(nonce, from, to, fromChainId, toChainId, message);
		verifyProof(rootHash, abi.encode(_key), message, branchMask, siblings);
		return _key;
	}

	function getMessageProof(uint256 nonce, address from, address to, uint256 fromChainId, uint256 toChainId, bytes memory message) public view returns (bytes32 rootHash, uint branchMask, bytes32[] memory siblings) {
		bytes32 key = getKey(nonce, from, to, getChainID(), toChainId, message);
		(uint _branchMask, bytes32[] memory _siblings) = getProof(abi.encode(key));
		return (root, _branchMask, _siblings);
	}

	function redeem(uint256 nonce, address from, uint256 fromChainId, bytes memory message, bytes32 rootHash, uint branchMask, bytes32[] memory siblings) public {
		require(remoteRoots[keccak256(abi.encode(rootHash,fromChainId))]);
		bytes32 key = verify(nonce, from, msg.sender, fromChainId, getChainID(), message, rootHash, branchMask, siblings);
		require(!redeemed[key], "Message already redeemed");
		redeemed[key] = true;
		emit Redeemed(key);
	}

	function addRemoteRoot(bytes32 root, uint256 chainID) public {
		if (bridgeType == 2) {
			//emit Debug(msg.sender);
			//emit Debug(address(getCrossDomainMessenger()));
			require(msg.sender == address(getCrossDomainMessenger()), "OVM_XCHAIN: messenger contract unauthenticated");

			//emit Debug(getCrossDomainMessenger().xDomainMessageSender());
			require(getCrossDomainMessenger().xDomainMessageSender() == address(l1RootBridge), "OVM_XCHAIN: wrong sender of cross-domain message");
		} else {
			// Both L1 and Arbitrum send directly from msg.sender
			require(msg.sender == address(l1RootBridge), "Only L1 bridge is allowed to add state roots");
		}
		remoteRoots[keccak256(abi.encode(root,chainID))] = true;
		emit ReceivedRoot(root,chainID);
	}

	function updateL1Bridge() public {
		bytes memory data = abi.encodeWithSelector(l1RootBridge.update.selector, root, getChainID());
		if (bridgeType == 2) {
			sendCrossDomainMessage(address(l1RootBridge), data, 1000000);
		} else if (bridgeType == 1) {
			// Arbitrum
			uint256 withdrawalId = arbsys.sendTxToL1(address(l1RootBridge), data);
			emit ArbitrumToL1TxCreated(withdrawalId);
		} else {
			// Local testing.  Send directly.
			l1RootBridge.update(root,getChainID());
		}
		emit SentRoot(root);
	}

	function updateL2Bridges(uint256[] memory toChainIDs) public {
		bytes memory data = abi.encodeWithSelector(l1RootBridge.updateAndSend.selector, root, getChainID(), toChainIDs);
		if (bridgeType == 2) {
			sendCrossDomainMessage(address(l1RootBridge), data, 1000000);
		} else if (bridgeType == 1) {
			// Arbitrum
			uint256 withdrawalId = arbsys.sendTxToL1(address(l1RootBridge), data);
			emit ArbitrumToL1TxCreated(withdrawalId);
		} else {
			// Local testing.  Send directly.
			l1RootBridge.updateAndSend(root,getChainID(),toChainIDs);
		}
		emit SentRoot(root);
	}

	function getChainID() public view returns (uint256) {
		uint256 id;
		assembly {
			id := chainid()
		}
		if (id == 1)	// Testing
			id = uint32(address(this));
		return id;
	}

}

