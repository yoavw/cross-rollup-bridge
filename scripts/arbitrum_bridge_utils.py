
import eth_utils

def to_32byte(val):
	return web3.toBytes(val).rjust(32, b'\0')

def to_32byte_hex(val):
	return web3.toHex(to_32byte(val))

def calculate_l2_transaction_hash(seq, l2_chain_id):
	return web3.keccak(eth_utils.conversions.decode_hex(to_32byte_hex(l2_chain_id)+eth_utils.remove_0x_prefix(to_32byte_hex(seq))))

def calculate_l2_retryable_transaction_hash(seq, l2_chain_id=212984383488152):
	return web3.keccak(calculate_l2_transaction_hash(seq, l2_chain_id)+to_32byte(1))

def calculate_l2_retryable_transaction_id(seq, l2_chain_id=212984383488152):
	return web3.keccak(calculate_l2_transaction_hash(seq, l2_chain_id)+to_32byte(0))

def get_seq_from_l1_transaction(l1_transaction):
	return int([a['topic2'] for a in filter(lambda a: a['topic1'] == '0xff64905f73a67fb594e0f940a8075a860db489ad991e032f48c81123eb52d60b', l1_transaction.events['(unknown)'])][0],16)

def tx_id_from_l1_transaction(l1_transaction):
	return calculate_l2_retryable_transaction_id(get_seq_from_l1_transaction(l1_transaction))

def tx_hash_from_l1_transaction(l1_transaction):
	return calculate_l2_retryable_transaction_hash(get_seq_from_l1_transaction(l1_transaction))

