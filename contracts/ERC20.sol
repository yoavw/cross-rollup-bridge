// SPDX-License-Identifier: MIT
pragma solidity >0.6.0 <0.8.0;

import "./IL2MessageBridge.sol";

/**
 * @title ERC20
 * @dev A super simple ERC20 implementation!
 */
contract ERC20 {

    /**********
     * Events *
     **********/

    event Transfer(
        address indexed _from,
        address indexed _to,
        uint256 _value
    );

    event Approval(
        address indexed _owner,
        address indexed _spender,
        uint256 _value
    );

	event SentToChain(uint256 indexed _nonce, address indexed _from, uint256 _value, uint256 _chainID);
	event ReceivedFromChain(address indexed _to, uint256 _chainID, uint256 _value);


    /*************
     * Variables *
     *************/

    mapping (address => uint256) public balances;
    mapping (address => mapping (address => uint256)) public allowances;

    // Some optional extra goodies.
    uint256 public totalSupply;
    string public name;

	IL2MessageBridge bridge;	// Cross-rollup bridge
	uint256 remoteChainId;		// ID of the other chain. The same ERC20 is expected to be deployed with the same address there.


    /***************
     * Constructor *
     ***************/

    /**
     * @param _initialSupply Initial maximum token supply.
     * @param _name A name for our ERC20 (technically optional, but it's fun ok jeez).
     */
    constructor(
        uint256 _initialSupply,
        string memory _name,
		IL2MessageBridge _bridge,
		uint256 _remoteChainId
    )
        public
    {
        balances[msg.sender] = _initialSupply;
        totalSupply = _initialSupply;
        name = _name;
		bridge = _bridge;
		remoteChainId = _remoteChainId;
    }


    /********************
     * Public Functions *
     ********************/

    /**
     * Checks the balance of an address.
     * @param _owner Address to check a balance for.
     * @return Balance of the address.
     */
    function balanceOf(
        address _owner
    )
        external
        view
        returns (
            uint256
        )
    {
        return balances[_owner];
    }

    /**
     * Transfers a balance from your account to someone else's account!
     * @param _to Address to transfer a balance to.
     * @param _amount Amount to transfer to the other account.
     * @return true if the transfer was successful.
     */
    function transfer(
        address _to,
        uint256 _amount
    )
        external
        returns (
            bool
        )
    {
        require(
            balances[msg.sender] >= _amount,
            "You don't have enough balance to make this transfer!"
        );

        balances[msg.sender] -= _amount;
        balances[_to] += _amount;

        emit Transfer(
            msg.sender,
            _to,
            _amount
        );

        return true;
    }

	/**
	 * Send an amount to another chain.
	 * Burn it in this chain and send a message to the cross-rollup bridge.
	 */
	function sendToOtherChain(uint256 _amount) external returns (bool) {
        require(
            balances[msg.sender] >= _amount,
            "You don't have enough balance to make this transfer!"
        );

        balances[msg.sender] -= _amount;
		totalSupply -= _amount;

		bytes memory data = abi.encode(msg.sender,_amount);
		uint256 nonce = bridge.send(address(this), data, remoteChainId);

		emit SentToChain(
			nonce,
            msg.sender,
            _amount,
            remoteChainId
        );

        return true;
	}

	/**
	 * Receive an amount that was sent from another chain.
	 * Verifies the message to the cross-rollup bridge and mints the tokens here.
	 */
	function receiveFromOtherChain(uint256 nonce, address to, uint256 amount, bytes32 rootHash, uint256 branchMask, bytes32[] memory siblings) external {
		bytes memory message = abi.encode(to,amount);
		bridge.redeem(nonce, address(this), remoteChainId, message, rootHash, branchMask, siblings);

		balances[to] += amount;
		totalSupply += amount;

		emit ReceivedFromChain(
            to,
            remoteChainId,
            amount
        );
	}

	/**
	 * Get a proof of a cross-rollup transfer.
	 * The proof will be used to redeem the tokens on the other chain.
	 */
	function getProof(uint256 _nonce, address from, uint256 amount) public view returns (uint256 nonce, address _from, uint256 _amount, bytes32 rootHash, uint256 branchMask, bytes32[] memory siblings) {
		bytes memory message = abi.encode(from,amount);
		(rootHash,branchMask,siblings) = bridge.getMessageProof(_nonce, address(this), address(this), bridge.getChainID(), remoteChainId, message);
		return (_nonce,from,amount,rootHash,branchMask,siblings);
	}

    /**
     * Transfers a balance from someone else's account to another account. You need an allowance
     * from the sending account for this to work!
     * @param _from Account to transfer a balance from.
     * @param _to Account to transfer a balance to.
     * @param _amount Amount to transfer to the other account.
     * @return true if the transfer was successful.
     */
    function transferFrom(
        address _from,
        address _to,
        uint256 _amount
    )
        external
        returns (
            bool
        )
    {
        require(
            balances[_from] >= _amount,
            "Can't transfer from the desired account because it doesn't have enough balance."
        );

        require(
            allowances[_from][msg.sender] >= _amount,
            "Can't transfer from the desired account because you don't have enough of an allowance."
        );

        balances[_to] += _amount;
        balances[_from] -= _amount;

        emit Transfer(
            _from,
            _to,
            _amount
        );

        return true;
    }

    /**
     * Approves an account to spend some amount from your account.
     * @param _spender Account to approve a balance for.
     * @param _amount Amount to allow the account to spend from your account.
     * @return true if the allowance was successful.
     */
    function approve(
        address _spender,
        uint256 _amount
    )
        external
        returns (
            bool
        )
    {
        allowances[msg.sender][_spender] = _amount;

        emit Approval(
            msg.sender,
            _spender,
            _amount
        );

        return true;
    }

    /**
     * Checks how much a given account is allowed to spend from another given account.
     * @param _owner Address of the account to check an allowance from.
     * @param _spender Address of the account trying to spend from the owner.
     * @return Allowance for the spender from the owner.
     */
    function allowance(
        address _owner,
        address _spender
    )
        external
        view
        returns (
            uint256
        )
    {
        return allowances[_owner][_spender];
    }
}
