import pytest
from brownie import *
from brownie.exceptions import *
import eth_utils

#@pytest.fixture(scope="session",autouse=True)
@pytest.fixture
def l1_bridge():
	return L1RootBridge.deploy([],[],[],[],{'from':a[0].address})

@pytest.fixture
def l2_bridge_1(l1_bridge):
	b = L2MessageBridge.deploy(l1_bridge.address,{'from':a[0].address})
	l1_bridge.setBridge(b.address, b.getChainID(), 0, b.address)
	return b

@pytest.fixture
def l2_bridge_2(l1_bridge):
	b = L2MessageBridge.deploy(l1_bridge.address,{'from':a[0].address})
	l1_bridge.setBridge(b.address, b.getChainID(), 0, b.address)
	return b

def new_message(l2_bridge_1,l2_bridge_2):
	ctr = 0
	while True:
		ctr += 1
		message = bytes(f'hello from network {ctr}', 'ascii')
		t = l2_bridge_1.send(a[1].address, message, l2_bridge_2.getChainID())
		yield (message,t.events['MessageStored'][0])

def test_deployment(l2_bridge_1, l2_bridge_2):
	assert l2_bridge_1.getChainID() != l2_bridge_2.getChainID()

def test_messages(l2_bridge_1, l2_bridge_2, l1_bridge):
	messages = new_message(l2_bridge_1, l2_bridge_2)
	msg,e = next(messages)
	assert e['nonce'] == l2_bridge_1.currentNonce() - 1
	assert e['from'] == a[0].address
	assert e['to'] == a[1].address
	assert e['fromChainId'] == l2_bridge_1.getChainID()
	assert e['toChainId'] == l2_bridge_2.getChainID()
	assert bytes(e['message']) == msg
	msg2,e2 = next(messages)
	assert e2['nonce'] == l2_bridge_1.currentNonce() - 1
	assert e2['from'] == a[0].address
	assert e2['to'] == a[1].address
	assert e2['fromChainId'] == l2_bridge_1.getChainID()
	assert e2['toChainId'] == l2_bridge_2.getChainID()
	assert bytes(e2['message']) == msg2
	assert msg != msg2
	assert e['nonce'] == e2['nonce'] - 1

def test_unknown_bridge(l2_bridge_1, l2_bridge_2, l1_bridge):
	unknown_bridge = L2MessageBridge.deploy(l1_bridge.address,{'from':a[0].address})
	try:
		t = unknown_bridge.updateL1Bridge()
		assert t.status == 0
	except(VirtualMachineError):
		pass

def get_proof(l2_bridge_1, message_event, sent_root_event):
	proof = l2_bridge_1.getMessageProof(message_event['nonce'], message_event['from'], message_event['to'], message_event['fromChainId'], message_event['toChainId'], message_event['message'], block_identifier=sent_root_event['blockNumber'])
	reported_root = sent_root_event['topics'][1].hex()
	if not reported_root.startswith('0x'):
		reported_root = '0x'+reported_root
	assert proof[0] == reported_root
	return proof

def redeem_message(l2_bridge_2, message_event, proof, by_address):
	print(proof[0])
	assert "Redeemed" in l2_bridge_2.redeem(message_event['nonce'], message_event['from'], message_event['fromChainId'], message_event['message'], proof[0], proof[1], proof[2], {'from':by_address}).events

def test_bridge(l2_bridge_1, l2_bridge_2, l1_bridge):
	f = web3.eth.filter({'fromBlock': web3.eth.block_number-200, 'toBlock': 'latest', 'address': l2_bridge_1.address, 'topics':[l2_bridge_1.topics['SentRoot']]})
	messages = new_message(l2_bridge_1, l2_bridge_2)
	# Send 3 messages
	msg1,e1 = next(messages)
	msg2,e2 = next(messages)
	msg3,e3 = next(messages)

	# make sure no root has been sent
	assert not f.get_all_entries()
	l2_bridge_1.updateL1Bridge().info()

	# send first root
	sent_root_events = f.get_all_entries()
	assert len(sent_root_events) == 1

	# send another message, altering the root but not sending it.
	msg4,e4 = next(messages)

	# get proofs for the first two messages based on the sent root (not the current one)
	proof1 = get_proof(l2_bridge_1, e1, sent_root_events[-1])
	proof2 = get_proof(l2_bridge_1, e2, sent_root_events[-1])

	# try to get a proof for msg4 which was sent after the root was sent.  Should fail.
	try:
		p = get_proof(l2_bridge_1, e4, sent_root_events[-1])
		assert not p
	except(VirtualMachineError):
		pass

	# redeem first message before root is delivered via l1.  Should fail.
	try:
		t = redeem_message(l2_bridge_2, e1, proof1, a[1].address)
		assert t.status == 0
	except(VirtualMachineError):
		pass

	# update root via l1
	l1_bridge.sendToL2(sent_root_events[-1]['topics'][1], l2_bridge_1.getChainID(), [l2_bridge_2.getChainID()])

	# now the first redeem should work
	redeem_message(l2_bridge_2, e1, proof1, a[1].address)

	# send the 2nd root.  Proofs made against the previous root should still work.  Redeem msg2 to verify.
	l2_bridge_1.updateL1Bridge().info()
	l1_bridge.sendToL2(l2_bridge_1.root(), l2_bridge_1.getChainID(), [l2_bridge_2.getChainID()]).info()
	redeem_message(l2_bridge_2, e2, proof2, a[1].address)

	# Verify that the 2nd L2 announced the roots it received.
	received_root_events = web3.eth.filter({'fromBlock': web3.eth.block_number-200, 'toBlock': 'latest', 'address': l2_bridge_2.address, 'topics':[l2_bridge_2.topics['ReceivedRoot']]}).get_all_entries()
	assert len(received_root_events) == 2
	print(received_root_events)
	print(sent_root_events)
	assert received_root_events[0]['topics'][1] == sent_root_events[-1]['topics'][1]
	assert received_root_events[1]['topics'][1] == l2_bridge_1.root()

	# get a proof for msg3, still based on the previous root which is not up to date.  Should work.  Redeem msg3 to verify.
	proof3 = get_proof(l2_bridge_1, e3, sent_root_events[-1])
	redeem_message(l2_bridge_2, e3, proof3, a[1].address)

	# update to the latest sent root
	sent_root_events = f.get_all_entries()
	assert len(sent_root_events) == 2

	# get a proof for msg using the newly sent root
	proof4 = get_proof(l2_bridge_1, e4, sent_root_events[-1])

	# try to redeem with the wrong recipient.  Should fail.
	try:
		t = redeem_message(l2_bridge_2, e4, proof4, a[0].address)
		assert t.status == 0
	except(VirtualMachineError):
		pass

	# now redeem with the correct recipient.  Should succeed.
	redeem_message(l2_bridge_2, e4, proof4, a[1].address)

	# try to double-redeem a message.  Should fail.
	try:
		t = redeem_message(l2_bridge_2, e4, proof4, a[1].address)
		assert t.status == 0
	except(VirtualMachineError):
		pass

	# 4 messages were redeemed
	assert len(web3.eth.filter({'fromBlock': web3.eth.block_number-200, 'toBlock': 'latest', 'address': l2_bridge_2.address, 'topics':[l2_bridge_2.topics['Redeemed']]}).get_all_entries()) == 4

