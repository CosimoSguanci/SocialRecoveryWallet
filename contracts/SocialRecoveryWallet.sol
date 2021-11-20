// SPDX-License-Identifier: MIT
pragma solidity ^0.8.3;

/**
Proposed solutions for vaulting:
- 2 wallets: 1 saving, 1 checking (daily uses), the latter contains few funds and doesn't neeed guardian approval for transaction execution
- The savings account by default needs N confirmations for executing a transactions, but has the possibility to have trusted/whitelisted recipients that do not
  need any guardian approval. Adding an address to the trusted addresses list need the approval by guardians
- Daily limit could be implemented by making use of block.timestamp

Proposed solution for privacy:
- hashing guardians addresses
- merkle proofs

For increased security and enforcing cooperation between owner and guardians
- User secret data hash needed to change spender key, and it could be biometric secret data
 */

contract SocialRecoveryWallet {
    event Deposit(address indexed sender, uint amount, uint balance);
    event SubmitTransaction(
        address indexed spender,
        uint indexed txIndex,
        address indexed to,
        uint value,
        bytes data
    );
    event ConfirmTransaction(address indexed guardian, uint indexed txIndex);
    event RevokeTxConfirmation(address indexed guardian, uint indexed txIndex);
    event ExecuteTransaction(address indexed spender, uint indexed txIndex);
    event SubmitChangeSpender(address indexed guardian, uint indexed reqIndex, address indexed newSpender);
    event ConfirmChangeSpender(address indexed guardian, uint indexed reqIndex, address indexed newSpender);
    event RevokeChangeSpender(address indexed guardian, uint indexed reqIndex, address indexed newSpender);
    event ExecuteChangeSpender(uint indexed reqIndex, address indexed newSpender);
    event RemoveTrustedAddress(address indexed spender, address indexed removedTrusted);
    event SubmitAddTrusted(address indexed spender, uint indexed reqIndex, address indexed newTrustedAddress);
    event ConfirmAddTrusted(address indexed guardian, uint indexed reqIndex, address indexed newTrustedAddress);
    event RevokeAddTrusted(address indexed guardian, uint indexed reqIndex, address indexed newTrustedAddress);
    event ExecuteAddTrusted(uint indexed reqIndex, address indexed newTrustedAddress);

    mapping(bytes32 => bool) public isGuardian;
    uint public numConfirmationsRequired; // Transactions
    uint public numConfirmationsRequiredToChangeSpender;
    uint public numConfirmationsRequiredToAddTrustedAddress;

    address public spender; // Who can spend the funds of the Social Recovery Wallet

    mapping(address => bool) public isTrustedAddress;

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

    struct AddTrustedAddressRequest {
      address newTrustedAddress;
      bool executed;
      uint numConfirmations;
    }

    // mapping from tx index => guardian => bool
    mapping(uint => mapping(address => bool)) public isConfirmed; // regards TRANSACTIONS

    Transaction[] public transactions;

    // mapping from change spender req index => guardian => bool
    mapping(uint => mapping(address => bool)) public isChangeSpenderRequestConfirmed; // regards CHANGE SPENDER REQUESTS

    ChangeSpenderRequest[] public changeSpenderRequests;

    // mapping from add trusted addr req index => guardian => bool
    mapping(uint => mapping(address => bool)) public isAddTrustedAddressRequestConfirmed; // regards CHANGE SPENDER REQUESTS

    AddTrustedAddressRequest[] public addTrustedAddressRequests;

    modifier onlyGuardian() {
        require(isGuardian[keccak256(abi.encodePacked(msg.sender))], "not guardian");
        _;
    }

    modifier onlySpender() {
        require(spender == msg.sender, "not spender");
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

    // modifiers regarding ADD TRUSTED ADDRESS REQs
    modifier addTrustedAddressRequestExists(uint _reqIndex) {
        require(_reqIndex < addTrustedAddressRequests.length, "add trusted address req does not exist");
        _;
    }

    modifier addTrustedAddressRequestNotExecuted(uint _reqIndex) {
        require(!addTrustedAddressRequests[_reqIndex].executed, "add trusted address req already executed");
        _;
    }

    modifier addTrustedAddressRequestNotConfirmed(uint _reqIndex) {
        require(!isAddTrustedAddressRequestConfirmed[_reqIndex][msg.sender], "add trusted address already confirmed");
        _;
    }

    constructor(address _spender, bytes32[] memory _guardians, address[] memory _trustedAddresses, uint _numConfirmationsRequired, uint _numConfirmationsRequiredToChangeSpender, uint _numConfirmationsRequiredToAddTrustedAddress) {
        require(_guardians.length > 0, "guardians required");
        require(
            _numConfirmationsRequired >= 0 &&
                _numConfirmationsRequired <= _guardians.length &&
                _numConfirmationsRequiredToChangeSpender >= 0 &&
                _numConfirmationsRequiredToChangeSpender <= _guardians.length &&
                _numConfirmationsRequiredToAddTrustedAddress >= 0 &&
                _numConfirmationsRequiredToAddTrustedAddress <= _guardians.length,
            "invalid number of required confirmations"
        );

        for (uint i = 0; i < _guardians.length; i++) {
            bytes32 guardian = _guardians[i];

            require(!isGuardian[guardian], "guardian not unique");

            isGuardian[guardian] = true;
        }

        for (uint i = 0; i < _trustedAddresses.length; i++){
            isTrustedAddress[_trustedAddresses[i]] = true;
        }

        spender = _spender;
        numConfirmationsRequired = _numConfirmationsRequired;
        numConfirmationsRequiredToChangeSpender = _numConfirmationsRequiredToChangeSpender;
        numConfirmationsRequiredToAddTrustedAddress = _numConfirmationsRequiredToAddTrustedAddress;
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

        if (isTrustedAddress[_to]){
            executeTransaction(txIndex);
        }
    }

    function confirmTransaction(uint _txIndex)
        external
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

    function executeTransaction(uint _txIndex) 
        public 
        onlySpender 
        txExists(_txIndex)
        notExecuted(_txIndex)
    {
        Transaction storage transaction = transactions[_txIndex];

        require(
            transaction.numConfirmations >= numConfirmationsRequired || isTrustedAddress[transaction.to],
            "cannot execute tx"
        );

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

        emit RevokeTxConfirmation(msg.sender, _txIndex);
    }

    // Function related to CHANGE SPENDER REQUESTS

    function submitChangeSpenderRequest(
        address _newSpender
    ) external onlyGuardian { // external visibility as it is not called inside the contract
        uint reqIndex = changeSpenderRequests.length;

        changeSpenderRequests.push(
            ChangeSpenderRequest({
                newSpender: _newSpender,
                executed: false,
                numConfirmations: 0
            })
        );
        
        confirmChangeSpenderRequest(reqIndex);

        emit SubmitChangeSpender(msg.sender, reqIndex, _newSpender);
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

        emit ConfirmChangeSpender(msg.sender, _reqIndex, req.newSpender);
    }

    function executeChangeSpenderRequest(uint _reqIndex) 
        private 
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

        emit ExecuteChangeSpender(_reqIndex, spender);
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

       emit RevokeChangeSpender(msg.sender, _reqIndex, req.newSpender);
    }

    // Functions related to ADD TRUSTED ADDRESSES REQUESTS

    function submitAddTrustedAddressRequest(
        address _newTrustedAddress
    ) external onlySpender {
        uint reqIndex = addTrustedAddressRequests.length;

        addTrustedAddressRequests.push(
            AddTrustedAddressRequest({
                newTrustedAddress: _newTrustedAddress,
                executed: false,
                numConfirmations: 0
            })
        );
        
        emit SubmitAddTrusted(msg.sender, reqIndex, _newTrustedAddress);
    }

    function confirmAddTrustedAddressRequest(uint _reqIndex)
        external
        onlyGuardian
        addTrustedAddressRequestExists(_reqIndex)
        addTrustedAddressRequestNotExecuted(_reqIndex)
        addTrustedAddressRequestNotConfirmed(_reqIndex)
    {
        AddTrustedAddressRequest storage req = addTrustedAddressRequests[_reqIndex];
        req.numConfirmations += 1;
        isAddTrustedAddressRequestConfirmed[_reqIndex][msg.sender] = true;
        
        if(req.numConfirmations >= numConfirmationsRequiredToAddTrustedAddress) {
            executeAddTrustedAddressRequest(_reqIndex);
        }

        emit ConfirmAddTrusted(msg.sender, _reqIndex, req.newTrustedAddress);
    }

    function executeAddTrustedAddressRequest(uint _reqIndex) 
        private 
        onlyGuardian 
        addTrustedAddressRequestExists(_reqIndex)
        addTrustedAddressRequestNotExecuted(_reqIndex)
    {
        AddTrustedAddressRequest storage req = addTrustedAddressRequests[_reqIndex];

        require(
            req.numConfirmations >= numConfirmationsRequiredToAddTrustedAddress,
            "cannot execute add trusted address req"
        );

        req.executed = true;

        isTrustedAddress[req.newTrustedAddress] = true;
        
        emit ExecuteAddTrusted(_reqIndex, req.newTrustedAddress);
    }

    function removeTrustedAddress(address _trusted) 
        external 
        onlySpender 
    {
        isTrustedAddress[_trusted] = false;

        emit RemoveTrustedAddress(msg.sender, _trusted);
    }


    function revokeAddTrustedAddressRequestConfirmation(uint _reqIndex)
        external
        onlyGuardian
        addTrustedAddressRequestExists(_reqIndex)
        addTrustedAddressRequestNotExecuted(_reqIndex)
    {
        AddTrustedAddressRequest storage req = addTrustedAddressRequests[_reqIndex];

        require(isAddTrustedAddressRequestConfirmed[_reqIndex][msg.sender], "add trusted address not confirmed");

        req.numConfirmations -= 1;
        isAddTrustedAddressRequestConfirmed[_reqIndex][msg.sender] = false;

        emit RevokeAddTrusted(msg.sender, _reqIndex, req.newTrustedAddress);
    }
    

    ///////////

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
