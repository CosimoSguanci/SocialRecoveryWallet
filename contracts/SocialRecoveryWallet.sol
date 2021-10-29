pragma solidity ^0.4.15;


/// @title Multisignature wallet - Allows multiple parties to agree on transactions before execution.
/// @author Stefan George - <stefan.george@consensys.net>
contract SocialRecoveryWallet {

    /*
     *  Events
     */
    event Confirmation(address indexed sender, uint indexed transactionId);
    event Revocation(address indexed sender, uint indexed transactionId);
    event Submission(uint indexed transactionId);
    event Execution(uint indexed transactionId);
    event ExecutionFailure(uint indexed transactionId);
    event Deposit(address indexed sender, uint value);
    event GuardianAddition(address indexed guardian);
    event GuardianRemoval(address indexed guardian);
    event RequirementChange(uint required);

    // recovery of lost keys + avoid loss in case of stolen keys

    /*
     *  Constants
     */
    uint constant public MAX_GUARDIAN_COUNT = 50;

    /*
     *  Storage
     */
    mapping (uint => Transaction) public transactions;
    mapping (uint => mapping (address => bool)) public confirmations;

    //mapping (address => address) public approvalsChangeSpender;
    //mapping (address => uint) public approvalsChangeSpenderCount;
    
    mapping (uint => mapping (address => bool)) public changeSpenderRequestsConfirmations;
    mapping (uint => ChangeSpenderRequest) public changeSpenderRequests;
    //mapping (uint => address) public newSpenders;
    uint public changeSpenderRequestCount;

    mapping (address => bool) public isGuardian;
    address[] public guardians;
    uint public required;
    uint public transactionCount;

    address public spender; // Who can spend the funds of the Social Recovery Wallet

    struct Transaction {
        address destination;
        uint value;
        bytes data;
        bool executed;
    }

    struct ChangeSpenderRequest {
      address newSpender;
      bool executed;
    }

    /*
     *  Modifiers
     */
    modifier onlyWallet() {
        require(msg.sender == address(this));
        _;
    }


    modifier isSpender() {
        require(msg.sender == spender);
        _;
    }

    modifier guardianDoesNotExist(address guardian) {
        require(!isGuardian[guardian]);
        _;
    }

    modifier guardianExists(address guardian) {
        require(isGuardian[guardian]);
        _;
    }

    modifier transactionExists(uint transactionId) {
        require(transactions[transactionId].destination != 0);
        _;
    }

    modifier confirmed(uint transactionId, address guardian) {
        require(confirmations[transactionId][guardian]);
        _;
    }

    modifier notConfirmed(uint transactionId, address guardian) {
        require(!confirmations[transactionId][guardian]);
        _;
    }

    modifier notExecuted(uint transactionId) {
        require(!transactions[transactionId].executed);
        _;
    }

    modifier notNull(address _address) {
        require(_address != 0);
        _;
    }

    modifier validRequirement(uint guardianCount, uint _required) {
        require(guardianCount <= MAX_GUARDIAN_COUNT
            && _required <= guardianCount
            && _required != 0
            && guardianCount != 0);
        _;
    }

    modifier changeSpenderRequestExists(uint changeSpenderRequestId) {
        require(changeSpenderRequests[changeSpenderRequestId].newSpender != 0);
        _;
    }

    
    modifier changeSpenderRequestConfirmed(uint changeSpenderRequestId, address guardian) {
        require(changeSpenderRequestsConfirmations[changeSpenderRequestId][guardian]);
        _;
    }

    modifier changeSpenderRequestNotExecuted(uint changeSpenderRequestId) {
        require(!changeSpenderRequests[changeSpenderRequestId].executed);
        _;
    }

    /// @dev Fallback function allows to deposit ether.
    function()
        payable
    {
        if (msg.value > 0)
            Deposit(msg.sender, msg.value);
    }

    /*
     * Public functions
     */
    /// @dev Contract constructor sets initial owners and required number of confirmations.
    /// @param _guardians List of initial owners.
    /// @param _required Number of required confirmations.
    function SocialRecoveryWallet(address[] _guardians, uint _required)
        public
        validRequirement(_guardians.length, _required)
    {
        spender = msg.sender;

        for (uint i=0; i<_guardians.length; i++) {
            require(!isGuardian[_guardians[i]] && _guardians[i] != 0);
            isGuardian[_guardians[i]] = true;
        }
        guardians = _guardians;
        required = _required;
    }

    /// @dev Allows to add a new owner. Transaction has to be sent by wallet.
    /// @param guardian Address of new owner.
    function addGuardian(address guardian)
        public
        onlyWallet
        guardianDoesNotExist(guardian)
        notNull(guardian)
        validRequirement(guardians.length + 1, required)
    {
        isGuardian[guardian] = true;
        guardians.push(guardian);
        GuardianAddition(guardian);
    }

    /// @dev Allows to remove an owner. Transaction has to be sent by wallet.
    /// @param guardian Address of owner.
    function removeGuardian(address guardian)
        public
        onlyWallet
        guardianExists(guardian)
    {
        isGuardian[guardian] = false;
        for (uint i=0; i<guardians.length - 1; i++)
            if (guardians[i] == guardian) {
                guardians[i] = guardians[guardians.length - 1];
                break;
            }
        guardians.length -= 1;
        if (required > guardians.length)
            changeRequirement(guardians.length);
        GuardianRemoval(guardian);
    }

    /// @dev Allows to replace an owner with a new owner. Transaction has to be sent by wallet.
    /// @param guardian Address of owner to be replaced.
    /// @param newGuardian Address of new owner.
    function replaceGuardian(address guardian, address newGuardian)
        public
        onlyWallet
        guardianExists(guardian)
        guardianDoesNotExist(newGuardian)
    {
        for (uint i=0; i<guardians.length; i++)
            if (guardians[i] == guardian) {
                guardians[i] = newGuardian;
                break;
            }
        isGuardian[guardian] = false;
        isGuardian[newGuardian] = true;
        GuardianRemoval(guardian);
        GuardianAddition(newGuardian);
    }

    /// @dev Allows to change the number of required confirmations. Transaction has to be sent by wallet.
    /// @param _required Number of required confirmations.
    function changeRequirement(uint _required)
        public
        onlyWallet
        validRequirement(guardians.length, _required)
    {
        required = _required;
        RequirementChange(_required);
    }

    function addChangeSpenderRequest(address newSpender)
        internal
        notNull(newSpender)
        returns (uint changeSpenderRequestId)
    {
        changeSpenderRequestId = changeSpenderRequestCount;
        changeSpenderRequests[changeSpenderRequestId] = ChangeSpenderRequest({
            newSpender: newSpender,
            executed: false
        });
        changeSpenderRequestCount += 1;
        //Submission(transactionId);
    }

    function submitChangeSpenderRequest(address newSpender)
        public
        returns (uint changeSpenderRequestId)
    {
        changeSpenderRequestId = addChangeSpenderRequest(newSpender);
        confirmChangeSpenderRequest(changeSpenderRequestId);
    }  
    
    // notConfirmed(transactionId, msg.sender)
    function confirmChangeSpenderRequest(uint changeSpenderRequestId)
        public
        guardianExists(msg.sender)
        changeSpenderRequestExists(changeSpenderRequestId)
    {

        changeSpenderRequestsConfirmations[changeSpenderRequestId][msg.sender] = true;
        //Confirmation(msg.sender, transactionId);
        executeChangeSpenderRequest(changeSpenderRequestId, changeSpenderRequests[changeSpenderRequestId].newSpender);
    } 

    /// @dev Allows an owner to submit and confirm a transaction.
    /// @param destination Transaction target address.
    /// @param value Transaction ether value.
    /// @param data Transaction data payload.
    /// @return Returns transaction ID.
    function submitTransaction(address destination, uint value, bytes data)
        public
        returns (uint transactionId)
    {
        transactionId = addTransaction(destination, value, data);
        //confirmTransaction(transactionId);
    }

    /// @dev Allows an owner to confirm a transaction.
    /// @param transactionId Transaction ID.
    function confirmTransaction(uint transactionId)
        public
        guardianExists(msg.sender)
        transactionExists(transactionId)
        notConfirmed(transactionId, msg.sender)
    {

        confirmations[transactionId][msg.sender] = true;
        Confirmation(msg.sender, transactionId);
        executeTransaction(transactionId);
    }

    /// @dev Allows an owner to revoke a confirmation for a transaction.
    /// @param transactionId Transaction ID.
    function revokeConfirmation(uint transactionId)
        public
        guardianExists(msg.sender)
        confirmed(transactionId, msg.sender)
        notExecuted(transactionId)
    {
        confirmations[transactionId][msg.sender] = false;
        Revocation(msg.sender, transactionId);
    }

    /// @dev Allows anyone to execute a confirmed transaction.
    /// @param transactionId Transaction ID.
    function executeTransaction(uint transactionId)
        public
        isSpender()
        confirmed(transactionId, msg.sender)
        notExecuted(transactionId)
    {
        if (isConfirmed(transactionId)) {
            Transaction storage txn = transactions[transactionId];
            txn.executed = true;
            if (external_call(txn.destination, txn.value, txn.data.length, txn.data))
                Execution(transactionId);
            else {
                ExecutionFailure(transactionId);
                txn.executed = false;
            }
        }
    }

    function executeChangeSpenderRequest(uint changeSpenderRequestId, address newSpender)
        public
        guardianExists(msg.sender)
        changeSpenderRequestConfirmed(changeSpenderRequestId, msg.sender)
        changeSpenderRequestNotExecuted(changeSpenderRequestId)
    {
        if (isChangeSpenderRequestConfirmed(changeSpenderRequestId)) {
            ChangeSpenderRequest storage req = changeSpenderRequests[changeSpenderRequestId];
            req.executed = true;
            
            spender = newSpender;
        }
    }

    // call has been separated into its own function in order to take advantage
    // of the Solidity's code generator to produce a loop that copies tx.data into memory.
    function external_call(address destination, uint value, uint dataLength, bytes data) private returns (bool) {
        bool result;
        assembly {
            let x := mload(0x40)   // "Allocate" memory for output (0x40 is where "free memory" pointer is stored by convention)
            let d := add(data, 32) // First 32 bytes are the padded length of data, so exclude that
            result := call(
                sub(gas, 34710),   // 34710 is the value that solidity is currently emitting
                                   // It includes callGas (700) + callVeryLow (3, to pay for SUB) + callValueTransferGas (9000) +
                                   // callNewAccountGas (25000, in case the destination address does not exist and needs creating)
                destination,
                value,
                d,
                dataLength,        // Size of the input (in bytes) - this is what fixes the padding problem
                x,
                0                  // Output is ignored, therefore the output size is zero
            )
        }
        return result;
    }

    /// @dev Returns the confirmation status of a transaction.
    /// @param transactionId Transaction ID.
    /// @return Confirmation status.
    function isConfirmed(uint transactionId)
        public
        constant
        returns (bool)
    {
        uint count = 0;
        for (uint i=0; i<guardians.length; i++) {
            if (confirmations[transactionId][guardians[i]])
                count += 1;
            if (count == required)
                return true;
        }
    }

    function isChangeSpenderRequestConfirmed(uint changeSpenderRequestId)
        public
        constant
        returns (bool)
    {
        uint count = 0;
        for (uint i=0; i<guardians.length; i++) {
            if (changeSpenderRequestsConfirmations[changeSpenderRequestId][guardians[i]])
                count += 1;
            if (count == required)
                return true;
        }
    }

    /*
     * Internal functions
     */
    /// @dev Adds a new transaction to the transaction mapping, if transaction does not exist yet.
    /// @param destination Transaction target address.
    /// @param value Transaction ether value.
    /// @param data Transaction data payload.
    /// @return Returns transaction ID.
    function addTransaction(address destination, uint value, bytes data)
        internal
        notNull(destination)
        returns (uint transactionId)
    {
        transactionId = transactionCount;
        transactions[transactionId] = Transaction({
            destination: destination,
            value: value,
            data: data,
            executed: false
        });
        transactionCount += 1;
        Submission(transactionId);
    }

    /*
     * Web3 call functions
     */
    /// @dev Returns number of confirmations of a transaction.
    /// @param transactionId Transaction ID.
    /// @return Number of confirmations.
    function getConfirmationCount(uint transactionId)
        public
        constant
        returns (uint count)
    {
        for (uint i=0; i<guardians.length; i++)
            if (confirmations[transactionId][guardians[i]])
                count += 1;
    }

    /// @dev Returns total number of transactions after filers are applied.
    /// @param pending Include pending transactions.
    /// @param executed Include executed transactions.
    /// @return Total number of transactions after filters are applied.
    function getTransactionCount(bool pending, bool executed)
        public
        constant
        returns (uint count)
    {
        for (uint i=0; i<transactionCount; i++)
            if (   pending && !transactions[i].executed
                || executed && transactions[i].executed)
                count += 1;
    }

    /// @dev Returns list of owners.
    /// @return List of owner addresses.
    function getGuardians()
        public
        constant
        returns (address[])
    {
        return guardians;
    }

    /// @dev Returns array with owner addresses, which confirmed transaction.
    /// @param transactionId Transaction ID.
    /// @return Returns array of owner addresses.
    function getConfirmations(uint transactionId)
        public
        constant
        returns (address[] _confirmations)
    {
        address[] memory confirmationsTemp = new address[](guardians.length);
        uint count = 0;
        uint i;
        for (i=0; i<guardians.length; i++)
            if (confirmations[transactionId][guardians[i]]) {
                confirmationsTemp[count] = guardians[i];
                count += 1;
            }
        _confirmations = new address[](count);
        for (i=0; i<count; i++)
            _confirmations[i] = confirmationsTemp[i];
    }

    /// @dev Returns list of transaction IDs in defined range.
    /// @param from Index start position of transaction array.
    /// @param to Index end position of transaction array.
    /// @param pending Include pending transactions.
    /// @param executed Include executed transactions.
    /// @return Returns array of transaction IDs.
    function getTransactionIds(uint from, uint to, bool pending, bool executed)
        public
        constant
        returns (uint[] _transactionIds)
    {
        uint[] memory transactionIdsTemp = new uint[](transactionCount);
        uint count = 0;
        uint i;
        for (i=0; i<transactionCount; i++)
            if (   pending && !transactions[i].executed
                || executed && transactions[i].executed)
            {
                transactionIdsTemp[count] = i;
                count += 1;
            }
        _transactionIds = new uint[](to - from);
        for (i=from; i<to; i++)
            _transactionIds[i - from] = transactionIdsTemp[i];
    }
}