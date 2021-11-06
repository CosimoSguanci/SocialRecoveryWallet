// SPDX-License-Identifier: MIT
pragma solidity ^0.8.3;

contract SocialRecoveryWalletNew {
    event Deposit(address indexed sender, uint amount, uint balance);
    event SubmitTransaction(
        address indexed guardian,
        uint indexed txIndex,
        address indexed to,
        uint value,
        bytes data
    );
    event ConfirmTransaction(address indexed guardian, uint indexed txIndex);
    event RevokeConfirmation(address indexed guardian, uint indexed txIndex);
    event ExecuteTransaction(address indexed guardian, uint indexed txIndex);

    address[] public guardians;
    mapping(address => bool) public isGuardian;
    uint public numConfirmationsRequired; // Transactions
    uint public numConfirmationsRequiredToChangeSpender;

    address public spender; // Who can spend the funds of the Social Recovery Wallet

    struct Transaction {
        address to;
        uint value;
        bytes data;
        bool executed;
        uint numConfirmations;
    }

    struct ChangeSpenderRequest {
      address newSpender;
      bool executed;
      uint numConfirmations;
    }

    // mapping from tx index => guardian => bool
    mapping(uint => mapping(address => bool)) public isConfirmed; // regards TRANSACTIONS

    Transaction[] public transactions;

    // mapping from change spender req index => guardian => bool
    mapping(uint => mapping(address => bool)) public isChangeSpenderRequestConfirmed; // regards CHANGE SPENDER REQUESTS

    ChangeSpenderRequest[] public changeSpenderRequests;

    modifier onlyGuardian() {
        require(isGuardian[msg.sender], "not guardian");
        _;
    }

    modifier onlySpender() {
        require(spender == msg.sender, "not guardian");
        _;
    }

    // modifiers regarding TRANSACTIONS
    modifier txExists(uint _txIndex) {
        require(_txIndex < transactions.length, "tx does not exist");
        _;
    }

    modifier notExecuted(uint _txIndex) {
        require(!transactions[_txIndex].executed, "tx already executed");
        _;
    }

    modifier notConfirmed(uint _txIndex) {
        require(!isConfirmed[_txIndex][msg.sender], "tx already confirmed");
        _;
    }

    // modifiers regarding CHANGE SPENDER REQs
    modifier changeSpenderRequestExists(uint _reqIndex) {
        require(_reqIndex < changeSpenderRequests.length, "change spender req does not exist");
        _;
    }

    modifier changeSpenderRequestNotExecuted(uint _reqIndex) {
        require(!changeSpenderRequests[_reqIndex].executed, "change spender req already executed");
        _;
    }

    modifier changeSpenderRequestNotConfirmed(uint _reqIndex) {
        require(!isChangeSpenderRequestConfirmed[_reqIndex][msg.sender], "change spender req already confirmed");
        _;
    }

    constructor(address _spender, address[] memory _guardians, uint _numConfirmationsRequired, uint _numConfirmationsRequiredToChangeSpender) {
        require(_guardians.length > 0, "guardians required");
        require(
            _numConfirmationsRequired > 0 &&
                _numConfirmationsRequired <= _guardians.length,
            "invalid number of required confirmations"
        );

        for (uint i = 0; i < _guardians.length; i++) {
            address guardian = _guardians[i];

            require(guardian != address(0), "invalid guardian");
            require(!isGuardian[guardian], "guardian not unique");

            isGuardian[guardian] = true;
            guardians.push(guardian);
        }

        spender = _spender;
        numConfirmationsRequired = _numConfirmationsRequired;
        numConfirmationsRequiredToChangeSpender = _numConfirmationsRequiredToChangeSpender;
    }

    receive() external payable {
        emit Deposit(msg.sender, msg.value, address(this).balance);
    }

    // Functions related to TRANSACTIONS
    function submitTransaction(
        address _to,
        uint _value,
        bytes memory _data
    ) public onlySpender {
        uint txIndex = transactions.length;

        transactions.push(
            Transaction({
                to: _to,
                value: _value,
                data: _data,
                executed: false,
                numConfirmations: 0
            })
        );

        emit SubmitTransaction(msg.sender, txIndex, _to, _value, _data);
    }

    function confirmTransaction(uint _txIndex)
        public
        onlyGuardian
        txExists(_txIndex)
        notExecuted(_txIndex)
        notConfirmed(_txIndex)
    {
        Transaction storage transaction = transactions[_txIndex];
        transaction.numConfirmations += 1;
        isConfirmed[_txIndex][msg.sender] = true;

        emit ConfirmTransaction(msg.sender, _txIndex);
    }

    // TODO only spender? who should call this?

    
    /*function executeTransaction(uint _txIndex) 
        public 
        onlyGuardian 
        txExists(_txIndex)
        notExecuted(_txIndex)
    {
        Transaction storage transaction = transactions[_txIndex];

        require(
            transaction.numConfirmations >= numConfirmationsRequired,
            "cannot execute tx"
        );

        transaction.executed = true;

        (bool success, ) = transaction.to.call{value: transaction.value}(
            transaction.data
        );
        require(success, "tx failed");

        emit ExecuteTransaction(msg.sender, _txIndex);
    }*/

    // TMP
    function executeTransaction(uint _txIndex) 
        public 
        onlySpender 
        txExists(_txIndex)
        notExecuted(_txIndex)
    {
        Transaction storage transaction = transactions[_txIndex];

        /*require(
            transaction.numConfirmations >= numConfirmationsRequired,
            "cannot execute tx"
        );*/

        transaction.executed = true;

        (bool success, ) = transaction.to.call{value: transaction.value}(
            transaction.data
        );
        require(success, "tx failed");

        emit ExecuteTransaction(msg.sender, _txIndex);
    }

    function revokeConfirmation(uint _txIndex)
        public
        onlyGuardian
        txExists(_txIndex)
        notExecuted(_txIndex)
    {
        Transaction storage transaction = transactions[_txIndex];

        require(isConfirmed[_txIndex][msg.sender], "tx not confirmed");

        transaction.numConfirmations -= 1;
        isConfirmed[_txIndex][msg.sender] = false;

        emit RevokeConfirmation(msg.sender, _txIndex);
    }

    // Function related to CHANGE SPENDER REQUESTS

    function submitChangeSpenderRequest(
        address _newSpender
    ) public onlyGuardian {
        uint reqIndex = changeSpenderRequests.length;

        changeSpenderRequests.push(
            ChangeSpenderRequest({
                newSpender: _newSpender,
                executed: false,
                numConfirmations: 0
            })
        );
        
        //isChangeSpenderRequestConfirmed[_reqIndex][msg.sender] = true;
        
        confirmChangeSpenderRequest(reqIndex);

        //emit SubmitTransaction(msg.sender, txIndex, _to, _value, _data);
    }

    function confirmChangeSpenderRequest(uint _reqIndex)
        public
        onlyGuardian
        changeSpenderRequestExists(_reqIndex)
        changeSpenderRequestNotExecuted(_reqIndex)
        changeSpenderRequestNotConfirmed(_reqIndex)
    {
        ChangeSpenderRequest storage req = changeSpenderRequests[_reqIndex];
        req.numConfirmations += 1;
        isChangeSpenderRequestConfirmed[_reqIndex][msg.sender] = true;
        
        if(req.numConfirmations >= numConfirmationsRequiredToChangeSpender) {
            executeChangeSpenderRequest(_reqIndex);
        }

        //emit ConfirmTransaction(msg.sender, _txIndex);
    }

    function executeChangeSpenderRequest(uint _reqIndex) 
        public 
        onlyGuardian 
        changeSpenderRequestExists(_reqIndex)
        changeSpenderRequestNotExecuted(_reqIndex)
    {
        ChangeSpenderRequest storage req = changeSpenderRequests[_reqIndex];

        require(
            req.numConfirmations >= numConfirmationsRequiredToChangeSpender,
            "cannot execute change spender req"
        );

        req.executed = true;

        spender = req.newSpender;

        //emit ExecuteTransaction(msg.sender, _txIndex);
    }

    function revokeChangeSpenderRequestConfirmation(uint _reqIndex)
        public
        onlyGuardian
        changeSpenderRequestExists(_reqIndex)
        changeSpenderRequestNotExecuted(_reqIndex)
    {
        ChangeSpenderRequest storage req = changeSpenderRequests[_reqIndex];

        require(isChangeSpenderRequestConfirmed[_reqIndex][msg.sender], "change spender req not confirmed");

        req.numConfirmations -= 1;
        isChangeSpenderRequestConfirmed[_reqIndex][msg.sender] = false;

       //emit RevokeConfirmation(msg.sender, _reqIndex);
    }

    function getGuardians() public view returns (address[] memory) {
        return guardians;
    }

    function getTransactionCount() public view returns (uint) {
        return transactions.length;
    }

    function getTransaction(uint _txIndex)
        public
        view
        returns (
            address to,
            uint value,
            bytes memory data,
            bool executed,
            uint numConfirmations
        )
    {
        Transaction storage transaction = transactions[_txIndex];

        return (
            transaction.to,
            transaction.value,
            transaction.data,
            transaction.executed,
            transaction.numConfirmations
        );
    }
}
