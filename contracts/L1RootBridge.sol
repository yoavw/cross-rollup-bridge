pragma solidity >=0.5.0 <0.8.0;

import "./L2MessageBridge.sol";
import "./optimism/Lib_Ownable.sol";
import "./arbitrum/Inbox.sol";
import "./arbitrum/Outbox.sol";

contract L1RootBridge is Ownable, Lib_AddressResolver, OVM_CrossDomainEnabled {

	event RootFromL2(bytes32 root, uint256 chainID);
	event Debug(bytes32 b);
	event Debug(uint256 u);
	event Debug(address a);

	event RetryableTicketCreated(uint256 indexed ticketId);
	event SentToOptimism(bytes32 root, uint256 chainID);

	mapping (bytes32 => bool) public roots;
	mapping (uint256 => address) public bridgeByChainId;
	mapping (uint256 => uint32) public bridgeTypeByChainId;
	mapping (uint256 => address) public helperByChainId;

	constructor(address[] memory bridges, uint256[] memory chainIDs, uint32[] memory bridgeTypes, address[] memory helpers) public
		OVM_CrossDomainEnabled(address(0)) // overridden later
		Lib_AddressResolver(address(0))	// overridden later
	{
		require(bridges.length == chainIDs.length && bridges.length == bridgeTypes.length && bridges.length == helpers.length);
		for (uint i = 0; i < bridges.length; i++) {
			setBridge(bridges[i], chainIDs[i], bridgeTypes[i], helpers[i]);
		}
	}

	function update(bytes32 root, uint256 chainID) public {
		uint32 bridgeType = bridgeTypeByChainId[chainID];
		if (bridgeType == 1) {
			// Arbitrum
			IInbox inbox = IInbox(helperByChainId[chainID]);
			IOutbox outbox = IOutbox(inbox.bridge().activeOutbox());
			require(msg.sender == address(outbox), "Arbitrum message not from outbox");
			address l2Sender = outbox.l2ToL1Sender();
			require(l2Sender == bridgeByChainId[chainID], "Aritrum call from the wrong address");
		} else if (bridgeType == 2) {
			// Optimism
			libAddressManager = Lib_AddressManager(helperByChainId[chainID]);
			messenger = resolve("Proxy__OVM_L1CrossDomainMessenger");
			//emit Debug(msg.sender);
			//emit Debug(messenger);
			//emit Debug(address(getCrossDomainMessenger()));
			require(msg.sender == address(getCrossDomainMessenger()), "OVM_XCHAIN: messenger contract unauthenticated");

			//emit Debug(getCrossDomainMessenger().xDomainMessageSender());
			require(getCrossDomainMessenger().xDomainMessageSender() == bridgeByChainId[chainID], "OVM_XCHAIN: wrong sender of cross-domain message");
		} else {
			// Direct
			require(bridgeByChainId[chainID] == msg.sender);
		}
		roots[keccak256(abi.encode(root,chainID))] = true;
		emit RootFromL2(root,chainID);
	}

	function sendToL2(bytes32 root, uint256 chainID, uint256[] memory toChainIDs) public {
		bytes32 encodedRoot = keccak256(abi.encode(root,chainID));
		require(roots[encodedRoot], "Unrecognized root");
		for (uint i = 0; i < toChainIDs.length; i++) {
			uint256 id = toChainIDs[i];
			bytes memory data = abi.encodeWithSignature("addRemoteRoot(bytes32,uint256)", root, chainID);
			if (bridgeTypeByChainId[id] == 0) {
				// Testing - direct sending
				bridgeByChainId[id].call(data);
			} else if (bridgeTypeByChainId[id] == 1) {
				// Arbitrum
				IInbox inbox = IInbox(helperByChainId[id]);
				uint256 ticketID = inbox.createRetryableTicket(bridgeByChainId[id], 0, 0, msg.sender, msg.sender, 9000000, 0, data);
				emit RetryableTicketCreated(ticketID);
			} else if (bridgeTypeByChainId[id] == 2) {
				// Optimism
				libAddressManager = Lib_AddressManager(helperByChainId[id]);
				messenger = resolve("Proxy__OVM_L1CrossDomainMessenger");
				sendCrossDomainMessage(bridgeByChainId[id], data, 1000000);
				emit SentToOptimism(root, chainID);
			}
		}
	}

	function updateAndSend(bytes32 root, uint256 chainID, uint256[] memory toChainIDs) public {
		update(root, chainID);
		sendToL2(root, chainID, toChainIDs);
	}

	function setBridge(address bridge, uint256 chainID, uint32 bridgeType, address helper) public onlyOwner {
		bridgeByChainId[chainID] = bridge;
		bridgeTypeByChainId[chainID] = bridgeType;
		helperByChainId[chainID] = helper;
		if (bridgeType == 2) {
			libAddressManager = Lib_AddressManager(helper);
			messenger = resolve("Proxy__OVM_L1CrossDomainMessenger");
			require(messenger != address(0), "Unable to find Optimism messenger");
		} else if (bridgeType == 1) {
			IInbox inbox = IInbox(helper);
			require(address(inbox.bridge()) != address(0), "Unable to find Arbitrum bridge");
		}
	}
}
