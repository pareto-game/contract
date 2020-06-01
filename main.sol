pragma solidity ^0.4.25;

import "./DataSets.sol";
import "./Help.sol";
import "./Util.sol";
import "./seroInterface.sol";

contract Pareto is SeroInterface{
    using SafeMath for uint256;

    //////////////////////////////////////// define constant
    
    uint256 constant calcDecimal = 1e18;
        
    /* bytes32 addrNoCodeHash = 0xc5d2460186f7233c927e7db2dcc703c0e500b653ca82273b7bfad8045d85a470;  */

    //////////////////////////////////////// define variable
    
    // define admin
    address superAdmin;
    mapping(address => uint256) admins;

    //////////////////// define system
    
    DataSets.SystemInfo public sInfo;

    // rid -> round info
    mapping (uint256 => DataSets.RoundInfo) private rInfo;

    //////////////////// define player
    
    // other variable
    uint256 public newPlayerID = 1;

    //////////////////////////////////////// event
    event LogBuyTicket(
        uint256 indexed roundIdx,
        address indexed pAddr,
        bytes32 name,
        uint256 tickets,
        uint256 payEth,
        uint256 time,
        uint256 buyID);

    event LogOpenTicket(
        uint256 indexed roundIdx,
        uint256 indexed openID,
        address indexed pAddr,
        uint256 tickets);

    event LogLockOpenTicket(
        uint256 indexed roundIdx,
        uint256 indexed openID,
        uint256 tickets);

    event LogFinishComputeOpenTicket(
        uint256 indexed roundIdx,
        uint256 indexed openID,
        uint256 awardTotal,
        uint256 basePrice);

    event LogOpenTicketWin(
        uint256 indexed roundIdx,
        uint256 indexed openID,
        address indexed pAddr,
        uint256 num,
        uint256 award,
        uint256 time,
        uint256 level,
        bytes32 name);

    event LogNextOpenTicket(
        uint256 indexed roundIdx,
        uint256 indexed openID);

    event LogReplaceLastPerson(
        uint256 indexed roundIdx,
        uint256 indexed oldID,
        uint256 newID);

    event LogAutoRebuy(
        uint256 indexed roundIdx,
        uint256 indexed pid,
        bool enable);

    event LogAff(
        uint256 indexed roundIdx,
        address indexed affAddr,
        bytes32 name,
        uint256 time,
        uint256 affEth);

    event LogFlag(
        uint256 indexed roundIdx,
        bool ended,
        bool terminate,
        bool urAwardEnd);

    //////////////////////////////////////// modifier

    // for solidity 5.0+
    /* modifier IsHuman() { */
    /*     // According to EIP-1052, 0x0 is the value returned for not-yet created accounts */
    /*     // and 0xc5d2460186f7233c927e7db2dcc703c0e500b653ca82273b7bfad8045d85a470 is returned */
    /*     // for accounts without code, i.e. `keccak256('')` */
    /*     bytes32 codehash; */
    /*     address account = msg.sender; */
    /*     // solhint-disable-next-line no-inline-assembly */
    /*     assembly { codehash := extcodehash(account) } */

    /*     require(codehash == 0x0 || codehash == addrNoCodeHash, "forbidden constract"); */
        
    /*     _; */
    /* } */

    // for solidity < 5.0
    modifier IsHuman() {
        address _addr = msg.sender;
        uint256 _codeLength;

        assembly {_codeLength := extcodesize(_addr)}
        require(_codeLength == 0, "sorry humans only");
        _;
    }

    modifier IsAdmin() {
        require(msg.sender == superAdmin || admins[msg.sender] == 1, "only admin");
        _;
    }

    modifier IsSuperAdmin() {
        require(superAdmin == msg.sender, "only super admin");
        _;
    }

    modifier IsRunning(){
        require(now >= rInfo[sInfo.rndIdx].rTime.startTime && !rInfo[sInfo.rndIdx].rFlag.ended, "not start or ended");
        _;
    }

    modifier IsSetting(){
        DataSets.RoundInfo storage _rInfo = rInfo[sInfo.rndIdx.add(1)];
        if( !_rInfo.rFlag.alreadInitParam){
            _rInfo.rFlag.alreadInitParam = true;
            initNewRound();
        }
        
        _;
    }

    //////////////////////////////////////// constructor
    
    constructor() public{
        sInfo.registerAffRatio = calcDecimal / 10;
        sInfo.registerEth = 300 ether;
      
        superAdmin = msg.sender;

        uint256 pid = registerPlayer();
        sInfo.devID = pid;
    }

    //////////////////////////////////////// super admin func
    
    function AddAdmin(address admin)
            public
            IsSuperAdmin(){
        admins[admin] = 1;
    }

    function DelAdmin(address admin)
            public
            IsSuperAdmin(){
        admins[admin] = 0;
    }

    function ChangeSuperAdmin(address suAdmin)
            public
            IsSuperAdmin(){
        require(suAdmin != address(0x0), "empty new super admin");
        superAdmin = suAdmin;
    }

    //////////////////////////////////////// admin func

    //////////////////// set param

    function PManualInit()
            public
            IsAdmin()
            IsSetting(){

        return;
    }
        
    
    function PChangePriceParam(
        uint256 a,
        uint256 b)
            public
            IsAdmin()
            IsSetting(){

        DataSets.SystemRndParamPrice storage _pPrice = rInfo[sInfo.rndIdx.add(1)].pPrice;
        _pPrice.a = a;
        _pPrice.aSqrt = a.mul(calcDecimal).sqrt();
        _pPrice.b = b;
    }

    function PChangeProtect(
        bytes32 secret,
        uint256 duration)
            public
            IsAdmin()
            IsSetting(){
        
        DataSets.SystemRndParamProtect storage _pProtect = rInfo[sInfo.rndIdx.add(1)].pProtect;
        _pProtect.secret = secret;
        _pProtect.duration = duration;
    }

    function PChangeICO(
        uint256 totalEth,
        uint256 perAddrEth)
            public
            IsAdmin()
            IsSetting(){

        DataSets.SystemRndParamICO storage _pICO = rInfo[sInfo.rndIdx.add(1)].pICO;
        _pICO.totalEth = totalEth;
        _pICO.perAddrEth = perAddrEth;
    }

    function PChangeAssignTicket(
        uint256 tAff,
        uint256 tShare,
        uint256 tAward,
        uint256 aBigWin,
        uint256 aOtherWin,
        uint256 aDiscount,
        uint256 lastPersonNum)
            public
            IsAdmin()
            IsSetting(){

        DataSets.SystemRndParamAssign storage _pAssign = rInfo[sInfo.rndIdx.add(1)].pAssign;

        _pAssign.tAff = tAff;
        _pAssign.tShare = tShare;
        _pAssign.tAward = tAward;

        _pAssign.aBigWin = aBigWin;
        _pAssign.aOtherWin = aOtherWin;
        _pAssign.aDiscount = aDiscount;
        _pAssign.lastPersonNum = lastPersonNum;
    }

    function PChangeOpenTicket(
        uint256[3] memory exp,
        uint256[3] memory factor,
        uint256 urRatio,
        uint256 ticketOpenMin)
            public
            IsAdmin()
            IsSetting(){

        DataSets.SystemRndParamOpenTicket storage _pOpenTicket = rInfo[sInfo.rndIdx.add(1)].pOpenTicket;

        for(uint256 i = 0; i < _pOpenTicket.exp.length; i++){
            _pOpenTicket.exp[i] = exp[i];
            _pOpenTicket.factor[i] = factor[i];
        }

        _pOpenTicket.urRatio = urRatio;
        _pOpenTicket.ticketOpenMin = ticketOpenMin;
    }

    function PChangeTime(
        uint256 timeMax,
        uint256 timeInit,
        uint256 timeAdd,
        uint256 startTimeInterval)
            public
            IsAdmin()
            IsSetting(){

        DataSets.SystemRndParamTime storage _pTime = rInfo[sInfo.rndIdx.add(1)].pTime;

        _pTime.timeMax = timeMax;
        _pTime.timeInit = timeInit;
        _pTime.timeAdd = timeAdd;
        _pTime.startTimeInterval = startTimeInterval;
    }

    function PChangeRatio(
        uint256 autoBuyFee,
        uint256[6] memory discountLevel,
        uint256[5] memory affRatio)
            public
            IsAdmin()
            IsSetting(){

        DataSets.SystemRndParamRatio storage _pRatio = rInfo[sInfo.rndIdx.add(1)].pRatio;
        _pRatio.autoBuyFee = autoBuyFee;

        for(uint256 i = 0; i < _pRatio.discountLevel.length; i++){
            _pRatio.discountLevel[i] = discountLevel[i];
        }

        for( i = 0; i < _pRatio.affRatio.length; i++){
            _pRatio.affRatio[i] = affRatio[i];
        }
    }

    function InitSecretHash(
        bytes32[10] memory hashs)
            public
            IsAdmin(){

        require(sInfo.finishSetSecretHash == 0, "can't modifier hashs");
        for(uint256 i = 0; i < sInfo.openSecretHashs.length; i++){
            sInfo.openSecretHashs[i] = hashs[i];
        }
    }

    function FinishSecretHash()
            public
            IsAdmin(){
        require(sInfo.finishSetSecretHash == 0, "can't double finish");

        for(uint256 i = 0; i < sInfo.openSecretHashs.length; i++){
            require(sInfo.openSecretHashs[i] != '', "empty secret hash");
        }
        
        sInfo.finishSetSecretHash = 1;
    }

    function StartNewRound()
            public
            IsAdmin()
            IsSetting(){

        startNewRound();
    }

    //////////////////// open ticket
    
    function LockOpenTicket()
            public
            IsAdmin(){
        
        Help.checkUpdateLockOpenTicket(sInfo, rInfo[sInfo.rndIdx]);
    }

    function ComputeOpenTickets(
        string memory key,
        bytes32 newHash,
        bool publishFlag)
            public
            IsAdmin(){

        Help.checkOpenTicketKey(key, newHash, sInfo);

        DataSets.RoundInfo storage _rInfo = rInfo[sInfo.rndIdx];

        Help.computeAwardNum(key, sInfo, _rInfo);

        if (publishFlag){
            Help.publishAward(10, sInfo, _rInfo);
            Help.terminateRound(sInfo, _rInfo);
        }
    }
    
    //////////////////// player func

    function ContinuePublishAward(uint256 num)
            public{
        DataSets.RoundInfo storage _rInfo = rInfo[sInfo.rndIdx];

        Help.publishAward(num, sInfo, _rInfo);

        Help.terminateRound(sInfo, _rInfo);
    }
    
    function BuyTicket(
        uint256 maxTickets,
        bytes32 affName,
        bytes memory key) 
            public
            payable
            IsHuman()
            IsRunning(){
        
        DataSets.RoundInfo storage _rInfo = rInfo[sInfo.rndIdx];
        
        // checkKey
        Help.checkProtectKey(key, _rInfo);

        // get player info
        uint256 pid = registerPlayer();
        DataSets.PlayerRndInfo storage pRndInfo = sInfo.playerRndInfo[pid][sInfo.rndIdx];
        DataSets.PlayerBaseInfo storage pBaseInfo = sInfo.playerBaseInfo[pid];

        // deal previous round
        if (pBaseInfo.lastRoundID != sInfo.rndIdx){
            updatePlayerLastRound(pBaseInfo, pRndInfo);
        } else {
            Help.updateMask(_rInfo, pBaseInfo, pRndInfo);
        }

        // deal round end
        if (Help.timeEnd(_rInfo)){
            Help.endTerminateRound(false, sInfo, _rInfo);
            pBaseInfo.avaiEth = pBaseInfo.avaiEth.add(msg.value);
            return;
        }
        
        // buy ticket
        Help.buyTickets(pBaseInfo, pRndInfo, msg.value, maxTickets, affName, rInfo[sInfo.rndIdx], sInfo);

    }

    function Withdraw()
            public
            IsHuman(){

        // get player info
        uint256 pid = registerPlayer();
        DataSets.PlayerRndInfo storage pRndInfo = sInfo.playerRndInfo[pid][sInfo.rndIdx];
        DataSets.PlayerBaseInfo storage pBaseInfo = sInfo.playerBaseInfo[pid];
        
        DataSets.RoundInfo storage _rInfo = rInfo[sInfo.rndIdx];        

        // deal previous round
        if (pBaseInfo.lastRoundID != sInfo.rndIdx){
            updatePlayerLastRound(pBaseInfo, pRndInfo);
        } else {
            Help.updateMask(_rInfo, pBaseInfo, pRndInfo);
        }

        if (Help.timeEnd(_rInfo)){
            Help.endTerminateRound(false, sInfo, _rInfo);
        }

        if (pBaseInfo.avaiEth > 0){
            uint256 earnEth = pBaseInfo.avaiEth;
            pBaseInfo.avaiEth = 0;
            sero_send(msg.sender, "sero", earnEth, "", 0);
              // msg.sender.transfer(earnEth);
        }
    }

    function ReBuyTicket(
        address pAddr,
        bytes32 affName,
        uint256 tickets)
            public
            IsHuman()
            IsRunning(){
        
        DataSets.RoundInfo storage _rInfo = rInfo[sInfo.rndIdx];

        uint256 tmp;
        
        // now tmp is pid !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
        bool self = true;
        if (pAddr != address(0x0) && pAddr != msg.sender) {
            self = false;
            tmp = sInfo.playerAddrIdx[pAddr];
            affName = '';
        } else{
            tmp = sInfo.playerAddrIdx[msg.sender];
        }

        require(tmp != 0, "not exist player");

        DataSets.PlayerRndInfo storage pRndInfo = sInfo.playerRndInfo[tmp][sInfo.rndIdx];
        DataSets.PlayerBaseInfo storage pBaseInfo = sInfo.playerBaseInfo[tmp];

        // deal previous round
        if(self && pBaseInfo.lastRoundID != sInfo.rndIdx){
            updatePlayerLastRound(pBaseInfo, pRndInfo);
        } else{
            Help.updateMask(_rInfo, pBaseInfo, pRndInfo);
        }

        // deal round end
        if (Help.timeEnd(_rInfo)){
            Help.endTerminateRound(false, sInfo, _rInfo);
            return;
        }

        uint256 payEth = pBaseInfo.avaiEth;
        require(payEth > 0, "not enough money");
        pBaseInfo.avaiEth = 0;
        
        if (self){
            Help.buyTickets(
                pBaseInfo,
                pRndInfo,
                payEth,
                tickets,
                affName,
                rInfo[sInfo.rndIdx],
                sInfo);
            return;
        }

        // now tmp is autoBuyFee!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
        tmp = rInfo[sInfo.rndIdx].pRatio.autoBuyFee;
        require(payEth > tmp.add(NewTicketPrice()), "the person not enough money");
        payEth = payEth.sub(tmp);
        
        Help.reBuyOther(
            payEth,
            pRndInfo,
            pBaseInfo,
            rInfo[sInfo.rndIdx],
            sInfo);

        sero_send(msg.sender, "sero", tmp, "", 0);
    }

    function AutoReBuy(
        bool enable,
        uint256 maxTickets)
            public
            IsHuman()
            IsRunning(){

        uint256 pid;
        pid = sInfo.playerAddrIdx[msg.sender];

        require(pid != 0, "not exist player, please direct buy ticket first");
        require(maxTickets > 0, "error: maxTickets = 0");
        
        DataSets.RoundInfo storage _rInfo = rInfo[sInfo.rndIdx];
        DataSets.PlayerRndInfo storage pRndInfo = sInfo.playerRndInfo[pid][sInfo.rndIdx];
        DataSets.PlayerBaseInfo storage pBaseInfo = sInfo.playerBaseInfo[pid];

        // deal previous round
        if (pBaseInfo.lastRoundID != sInfo.rndIdx){
            updatePlayerLastRound(pBaseInfo, pRndInfo);
        } else {
            Help.updateMask(_rInfo, pBaseInfo, pRndInfo);
        }

        // deal round end
        if (Help.timeEnd(_rInfo)){
            Help.endTerminateRound(false, sInfo, _rInfo);
            return;
        }
        
        pRndInfo.enableAutoBuy = enable;
        pRndInfo.autoBuyTicketNum = maxTickets;

        emit LogAutoRebuy(sInfo.rndIdx, pid, enable);
    }

    function OpenTicket(
        uint256 tickets,
        bytes32 openHash)
            public
            IsHuman()
            IsRunning(){

        uint256 pid;
        pid = sInfo.playerAddrIdx[msg.sender];

        require(pid != 0, "no user");

        DataSets.RoundInfo storage _rInfo = rInfo[sInfo.rndIdx];

        DataSets.PlayerRndInfo storage pRndInfo = sInfo.playerRndInfo[pid][sInfo.rndIdx];
        DataSets.SystemRndOpenTicket storage _rOpenTicket = _rInfo.rOpenTicket;

        require(_rOpenTicket.step == 0, "open ticket step error");
        require(pRndInfo.nowTickets.sub(pRndInfo.penddingTickets) >= tickets, "ticket not enough");

        Help.updateMask(_rInfo, sInfo.playerBaseInfo[pid], pRndInfo);        

        // deal round end
        if (Help.timeEnd(_rInfo)){
            Help.endTerminateRound(false, sInfo, _rInfo);
            return;
        }

        // update tickets info
        if (pRndInfo.lastOpenTicketCounterID != _rOpenTicket.nowOpenTicketCounterID){
            pRndInfo.penddingTickets = tickets;
            pRndInfo.lastOpenTicketCounterID = _rOpenTicket.nowOpenTicketCounterID;
        } else {
            pRndInfo.penddingTickets = pRndInfo.penddingTickets.add(tickets);
        }

        bool newOpen = false;
        if(pRndInfo.waitForOpenID == 0){
            pRndInfo.waitForOpenID = _rOpenTicket.newWaitForOpenID;
            _rOpenTicket.newWaitForOpenID = _rOpenTicket.newWaitForOpenID.add(1);
            newOpen = true;
        }

        if(pRndInfo.waitForOpenID == _rOpenTicket.waitForOpen.length){
            DataSets.PersonOpenTicketInfo memory _pOpenTicketInfo;
            _pOpenTicketInfo.pid = pid;
            _pOpenTicketInfo.tickets = tickets;
            _rOpenTicket.waitForOpen.push(_pOpenTicketInfo);
        } else {
            DataSets.PersonOpenTicketInfo storage pOpenTicketInfo = _rOpenTicket.waitForOpen[pRndInfo.waitForOpenID];
            if(newOpen){
                pOpenTicketInfo.tickets = tickets;
                pOpenTicketInfo.pid = pid;
            } else{
                pOpenTicketInfo.tickets = pOpenTicketInfo.tickets.add(tickets);
            }
        }

        _rOpenTicket.nowOpenHash = keccak256(abi.encodePacked(_rOpenTicket.nowOpenHash, openHash));
        _rOpenTicket.penddingTickets = _rOpenTicket.penddingTickets.add(tickets);

        emit LogOpenTicket(sInfo.rndIdx, _rOpenTicket.nowOpenTicketCounterID, msg.sender, tickets);
        return;
    }

    function RegisterName(
        string memory name,
        bytes32 affName)
            public
            payable
            IsHuman(){

        uint256 pid = registerPlayer();

        Help.registerName(name, affName, pid, msg.value, sInfo);
    }

    //////////////////////////////////////// view func
    function NewTicketPrice() public view returns (uint256){
        return Help.newTicketPrice(rInfo[sInfo.rndIdx]);
    }

    function TicketComputeEth(uint256 tickets) public view returns(uint256){
        return Help.computeTicketPayEth(rInfo[sInfo.rndIdx], tickets);
    }

    function EthComputeTicket(uint256 eth) public view returns(uint256){
        return Help.computePayEthTickets(rInfo[sInfo.rndIdx], eth);
    }

    function ComputeDiscount(uint256 pid, uint256 eth) public view returns(uint256){

        uint8 level = Help.getNowRndLevel(
            sInfo.playerBaseInfo[pid],
            sInfo.playerRndInfo[pid][sInfo.rndIdx],
            sInfo);
        
        return Help.computeDiscountByTotal(
            rInfo[sInfo.rndIdx],
            eth,
            level);
    }

    function GetNowSystemInfo()
            public
            view
            returns(
                uint256 roundIdx,
                bool ended,
                bool terminate,
                bool urAwardEnd,
                uint256 openTicketStep,
                uint256 startTime,
                uint256 endTime,
                uint256 tickets,
                uint256 eth,
                uint256 penddingTickets,
                uint256 discountPool,
                uint256 awardPool,
                uint256 openTicketCounterID,
                uint256 nextPrice){
        
        roundIdx = sInfo.rndIdx;
        // ended = Help.timeEnd(rInfo[sInfo.rndIdx]);
        ended = rInfo[sInfo.rndIdx].rFlag.ended;
        terminate = rInfo[sInfo.rndIdx].rFlag.terminate;
        urAwardEnd = rInfo[sInfo.rndIdx].rFlag.urAwardEnd;
        openTicketStep = rInfo[sInfo.rndIdx].rOpenTicket.step;
        startTime = rInfo[sInfo.rndIdx].rTime.startTime;
        endTime = rInfo[sInfo.rndIdx].rTime.endTime;
        tickets = rInfo[sInfo.rndIdx].rTicket.tickets;
        eth = rInfo[sInfo.rndIdx].rTicket.eth;
        penddingTickets = rInfo[sInfo.rndIdx].rOpenTicket.penddingTickets;
        discountPool = rInfo[sInfo.rndIdx].rPool.discountPool;
        awardPool = rInfo[sInfo.rndIdx].rPool.awardPool;
        openTicketCounterID = rInfo[sInfo.rndIdx].rOpenTicket.nowOpenTicketCounterID;
        nextPrice = NewTicketPrice();
        return;
    }

    function GetNowSystemInfo2()
            public
            view
            returns(
                uint256 totalSharedEth,
                uint256 totalAffEth,
                uint256 totalTickets,
                uint256 totalWinEth,
                uint256[3] totalAwardNum,
                uint256 ticketOpenMin,
                uint256[3] factor,
                uint256 timeAdd,
                uint256 tAff,
                uint256 tShare,
                uint256 tAward,
                uint256 aBigWin,
                uint256 icoTotalEth,
                uint256 icoPerAddrEth){

        totalSharedEth = rInfo[sInfo.rndIdx].rTicket.totalSharedEth;
        totalAffEth = rInfo[sInfo.rndIdx].rTicket.totalAffEth;
        totalTickets = rInfo[sInfo.rndIdx].rTicket.totalTickets;
        totalWinEth = rInfo[sInfo.rndIdx].rOpenTicket.totalWinEth;
        totalAwardNum = rInfo[sInfo.rndIdx].rOpenTicket.totalAwardNum;
        ticketOpenMin = rInfo[sInfo.rndIdx].pOpenTicket.ticketOpenMin;
        factor = rInfo[sInfo.rndIdx].pOpenTicket.factor;
        timeAdd = rInfo[sInfo.rndIdx].pTime.timeAdd;
        tAff = rInfo[sInfo.rndIdx].pAssign.tAff;
        tShare = rInfo[sInfo.rndIdx].pAssign.tShare;
        tAward = rInfo[sInfo.rndIdx].pAssign.tAward;
        aBigWin = rInfo[sInfo.rndIdx].pAssign.aBigWin;
        icoTotalEth = rInfo[sInfo.rndIdx].pICO.totalEth;
        icoPerAddrEth = rInfo[sInfo.rndIdx].pICO.perAddrEth;

        return;
    }
    
    function GetNowPlayerInfo(uint256 pid)
            public
            view
            returns(
                bool enableAutoBuy,
                uint8 level,
                uint256 eth,
                uint256 payEth,
                uint256 totalTickets,
                uint256 nowTickets,
                uint256 penddingTickets,
                uint256 sharedEth,
                uint256 avaiEth){

        DataSets.PlayerRndInfo storage pRndInfo = sInfo.playerRndInfo[pid][sInfo.rndIdx];
        enableAutoBuy = pRndInfo.enableAutoBuy;
        level = Help.getNowRndLevel(
            sInfo.playerBaseInfo[pid],
            pRndInfo,
            sInfo);

        eth = pRndInfo.eth;
        payEth = pRndInfo.payEth;
        totalTickets = pRndInfo.totalTickets;

        bool cleanOpenTicket;
        // tmp use, now avaiEth = lastRoundID
        avaiEth = sInfo.playerBaseInfo[pid].lastRoundID;
        (sharedEth, , nowTickets, cleanOpenTicket) = Help.getUnmaskEth(rInfo[avaiEth], pRndInfo);
        
        avaiEth = sInfo.playerBaseInfo[pid].avaiEth.add(sharedEth);
        sharedEth = sInfo.playerBaseInfo[pid].sharedEth.add(sharedEth);

        nowTickets = pRndInfo.nowTickets.sub(nowTickets);
        if (!cleanOpenTicket){
            penddingTickets = pRndInfo.penddingTickets;
        }
        return;
    }

    function GetPlayerRndInfo(uint256 roundID, uint256 pid)
            public
            view
            returns(
                bool enableAutoBuy,
                uint8 level,
                uint256 lastPersonCounter,
                uint256 autoBuyTicketNum,
                uint256 eth,
                uint256 payEth,
                uint256 nowTickets,
                uint256 totalTickets,
                uint256 mask,
                uint256 penddingTickets,
                uint256 waitForOpenID,
                uint256 lastOpenTicketCounterID){

        enableAutoBuy = sInfo.playerRndInfo[pid][roundID].enableAutoBuy;
        level = sInfo.playerRndInfo[pid][roundID].level;
        lastPersonCounter = sInfo.playerRndInfo[pid][roundID].lastPersonCounter;
        autoBuyTicketNum = sInfo.playerRndInfo[pid][roundID].autoBuyTicketNum;
        eth = sInfo.playerRndInfo[pid][roundID].eth;
        payEth = sInfo.playerRndInfo[pid][roundID].payEth;
        nowTickets = sInfo.playerRndInfo[pid][roundID].nowTickets;
        totalTickets = sInfo.playerRndInfo[pid][roundID].totalTickets;
        mask = sInfo.playerRndInfo[pid][roundID].mask;
        penddingTickets = sInfo.playerRndInfo[pid][roundID].penddingTickets;
        waitForOpenID = sInfo.playerRndInfo[pid][roundID].waitForOpenID;
        lastOpenTicketCounterID = sInfo.playerRndInfo[pid][roundID].lastOpenTicketCounterID;
        return;
    }

    function IdentifyNameExist(bytes32 affname)
            public
            view
            returns(bool exist){

        uint256 pid = sInfo.playerAffNameIdx[affname];
        if (pid == 0){
            return false;
        } 
        return true;
    }

    function GetPlayerBaseInfo(uint256 pid, address _addr, bytes32 affname)
            public
            view
            returns(
                bytes32 name,
                address addr,
                uint256 ID,
                uint256 lastAffID,
                uint256 lastRoundID,
                uint256 winEth,
                uint256 affEth,
                uint256 sharedEth,
                uint256 avaiEth){
        if(pid == 0){
            if(_addr != address(0x0)){
               pid = sInfo.playerAddrIdx[_addr];
            }

            if(pid == 0 && affname != ''){
                pid = sInfo.playerAffNameIdx[affname];
            }
        }

        if (pid == 0){
            return;
        }

        DataSets.PlayerBaseInfo storage _pBInfo = sInfo.playerBaseInfo[pid];

        name = _pBInfo.name;
        addr = _pBInfo.addr;
        ID = _pBInfo.ID;
        lastAffID = _pBInfo.lastAffID;
        lastRoundID = _pBInfo.lastRoundID;
        winEth = _pBInfo.winEth;
        affEth = _pBInfo.affEth;
        sharedEth = _pBInfo.sharedEth;
        avaiEth = _pBInfo.avaiEth;
        return;
    }

    function GetOpenSecretHashs()
            public
            view
            returns(bytes32[10] memory openSecretHashs){
        return sInfo.openSecretHashs;
    }

    function GetRFlag(uint256 roundID)
            public
            view
            returns(
                bool alreadInitParam,
                bool ended,
                bool terminate,
                bool urAwardEnd){
        
        DataSets.SystemRndFlag storage _rFlag = rInfo[roundID].rFlag;
        alreadInitParam = _rFlag.alreadInitParam;
        ended = _rFlag.ended;
        terminate = _rFlag.terminate;
        urAwardEnd = _rFlag.urAwardEnd;
        return;
    }

    function GetRTime(uint256 roundID)
            public
            view
            returns(
                uint256 startTime,
                uint256 endTime){

        DataSets.SystemRndTime storage _rTime = rInfo[roundID].rTime;

        startTime = _rTime.startTime;
        endTime = _rTime.endTime;
        return;
    }


    function GetRTicket(uint256 roundID)
            public
            view
            returns(
                uint256 eth,
                uint256 tickets,
                uint256 mask,
                uint256 newBuyID,
                uint256 lastQueueFirst,
                uint256 totalSharedEth,
                uint256 totalAffEth,
                uint256 totalTickets){

        DataSets.SystemRndTicket storage _rTicket = rInfo[roundID].rTicket;

        eth = _rTicket.eth;
        tickets = _rTicket.tickets;
        mask = _rTicket.mask;
        newBuyID = _rTicket.newBuyID;
        lastQueueFirst = _rTicket.lastQueueFirst;
        totalSharedEth = _rTicket.totalSharedEth;
        totalAffEth = _rTicket.totalAffEth;
        totalTickets = _rTicket.totalTickets;
        return;
    }

    function GetLastPersonQueue(uint256 roundID, uint256 idx)
            public
            view
            returns(
                uint256 pid,
                uint256 tickets){
        DataSets.SystemRndTicket storage _rTicket = rInfo[roundID].rTicket;

        pid = _rTicket.lastPersonQueue[idx].pid;
        tickets = _rTicket.lastPersonQueue[idx].tickets;
        return;
    }

    function GetMaskSnap(uint256 roundID, uint256 openID)
            public
            view
            returns(uint256 mask){

        DataSets.SystemRndOpenTicket storage _rOpenTicket = rInfo[roundID].rOpenTicket;

        return _rOpenTicket.maskSnap[openID];
    }

    function GetDebugOpenTicket(uint256 roundID)
            public
            view
            returns(
                uint256[3] probability,
                uint256[3] exp){
        
        DataSets.SystemRndOpenTicket storage _rOpenTicket = rInfo[roundID].rOpenTicket;

        probability = _rOpenTicket._probability;
        exp = _rOpenTicket._exp;
        return;
    }
                

    function GetROpenTicket(uint256 roundID)
            public
            view
            returns(
                uint256 k,
                uint256 fk,
                uint256 step,
                uint256 nowOpenTicketCounterID,
                uint256 penddingTickets,
                bytes32 nowOpenHash,
                uint256 newWaitForOpenID,
                uint256[3] nowAwardNum,
                uint256[3] award,
                uint256 nowURAwardNum){

        DataSets.SystemRndOpenTicket storage _rOpenTicket = rInfo[roundID].rOpenTicket;

        k = _rOpenTicket.k;
        fk = _rOpenTicket.fk;
        step = _rOpenTicket.step;
        nowOpenTicketCounterID = _rOpenTicket.nowOpenTicketCounterID;
        penddingTickets = _rOpenTicket.penddingTickets;
        nowOpenHash = _rOpenTicket.nowOpenHash;
        newWaitForOpenID = _rOpenTicket.newWaitForOpenID;
        nowAwardNum = _rOpenTicket.nowAwardNum;
        award = _rOpenTicket.award;
        nowURAwardNum = _rOpenTicket.nowURAwardNum;
        return;
    }

    function GetWaitForOpen(uint256 roundID, uint256 idx)
            public
            view
            returns(
                uint256 pid,
                uint256 tickets){
        DataSets.SystemRndOpenTicket storage _rOpenTicket = rInfo[roundID].rOpenTicket;

        pid = _rOpenTicket.waitForOpen[idx].pid;
        tickets = _rOpenTicket.waitForOpen[idx].tickets;
        return;
    }

    function GetRPool(uint256 roundID)
            public
            view
            returns(
                uint256 discountPool,
                uint256 awardPool,
                uint256 nextDiscountPool){
        DataSets.SystemRndPool storage _rPool = rInfo[roundID].rPool;

        discountPool = _rPool.discountPool;
        awardPool = _rPool.awardPool;
        nextDiscountPool = _rPool.nextDiscountPool;
        return;
    }        
                

    function GetPriceParam(uint256 roundID)
            public
            view
            returns(
                uint256 a,
                uint256 aSqrt, 
                uint256 b){
        DataSets.SystemRndParamPrice storage _pPrice = rInfo[roundID].pPrice;
        a = _pPrice.a;
        aSqrt = _pPrice.aSqrt;
        b = _pPrice.b;
        return;
    }

    function GetProtectParam(uint256 roundID)
            public
            view
            returns(
                bytes32 secret,
                uint256 duration){
        DataSets.SystemRndParamProtect storage _pProtect = rInfo[roundID].pProtect;
        secret = _pProtect.secret;
        duration = _pProtect.duration;
        return;
    }

    function GetICOParam(uint256 roundID)
            public
            view
            returns(
                uint256 totalEth,
                uint256 perAddrEth){

        DataSets.SystemRndParamICO storage _pICO = rInfo[roundID].pICO;
        totalEth = _pICO.totalEth;
        perAddrEth = _pICO.perAddrEth;
        return;
    }

    function GetAssignTicketParam(uint256 roundID)
            public
            view
            returns(
                uint256 tAff,
                uint256 tShare,
                uint256 tAward,
                uint256 aBigWin,
                uint256 aOtherWin,
                uint256 aDiscount,
                uint256 lastPersonNum){
                
        DataSets.SystemRndParamAssign storage _pAssign = rInfo[roundID].pAssign;

        tAff = _pAssign.tAff;
        tShare = _pAssign.tShare;
        tAward = _pAssign.tAward;

        aBigWin = _pAssign.aBigWin;
        aOtherWin = _pAssign.aOtherWin;
        aDiscount = _pAssign.aDiscount;
        lastPersonNum = _pAssign.lastPersonNum;
        return;
    }

    function GetOpenTicketParam(uint256 roundID)
            public
            view
            returns(
                uint256[3] memory exp,
                uint256[3] memory factor,
                uint256 urRatio,
                uint256 ticketOpenMin){


        DataSets.SystemRndParamOpenTicket storage _pOpenTicket = rInfo[roundID].pOpenTicket;

        exp = _pOpenTicket.exp;
        factor = _pOpenTicket.factor;
        urRatio = _pOpenTicket.urRatio;
        ticketOpenMin = _pOpenTicket.ticketOpenMin;
    }

    function GetTimeParam(uint256 roundID)
            public
            view
            returns(
                uint256 timeMax,
                uint256 timeInit,
                uint256 timeAdd,
                uint256 startTimeInterval){

        DataSets.SystemRndParamTime storage _pTime = rInfo[roundID].pTime;

        timeMax = _pTime.timeMax;
        timeInit = _pTime.timeInit;
        timeAdd = _pTime.timeAdd;
        startTimeInterval = _pTime.startTimeInterval;
        return;
    }

    function GetRatioParam(uint256 roundID)
            public
            view
            returns(
                uint256 autoBuyFee,
                uint256[6] memory discountLevel,
                uint256[5] memory affRatio){

        DataSets.SystemRndParamRatio storage _pRatio = rInfo[roundID].pRatio;
        
        autoBuyFee = _pRatio.autoBuyFee;
        discountLevel = _pRatio.discountLevel;
        affRatio = _pRatio.affRatio;
        return;
    }

    //////////////////////////////////////// private func

    function updatePlayerLastRound(
        DataSets.PlayerBaseInfo storage pBaseInfo,
        DataSets.PlayerRndInfo storage pRndInfo)
            private{
        
        uint256 lastRndIdx = pBaseInfo.lastRoundID;
        
        Help.updateMask(
            rInfo[lastRndIdx],
            pBaseInfo,
            sInfo.playerRndInfo[pBaseInfo.ID][lastRndIdx]);

        if(!pRndInfo.ensureLevel){
            uint8 level = Help.getNowRndLevel(pBaseInfo, pRndInfo, sInfo);
            pBaseInfo.lastRoundID = sInfo.rndIdx;
            pRndInfo.level = level;
            pRndInfo.ensureLevel = true;
        }
    }


    //////////////////// register
    function registerPlayer()
            private
            returns (uint256 pid){

        pid = sInfo.playerAddrIdx[msg.sender];
        if (pid == 0){
            // register new id
            pid = newPlayerID;

            newPlayerID = newPlayerID.add(1);

            DataSets.PlayerBaseInfo storage pBaseInfo = sInfo.playerBaseInfo[pid];
            pBaseInfo.addr = msg.sender;
            pBaseInfo.ID = pid;
            pBaseInfo.lastRoundID = sInfo.rndIdx;
            
            sInfo.playerAddrIdx[msg.sender] = pid;
        }
        return pid;
    }
    
    //////////////////// round func

    function initFirstRound()
            private{
        PChangePriceParam(calcDecimal.mul(1212) / 1e6, calcDecimal.mul(8));
        PChangeProtect('', 30 minutes);
        PChangeICO(100000 ether, 5000 ether);
        PChangeAssignTicket(
            calcDecimal.mul(20) / 100,
            calcDecimal.mul(40) / 100,
            calcDecimal.mul(30) / 100,
            calcDecimal.mul(56) / 100,
            calcDecimal.mul(24) / 100,
            calcDecimal.mul(10) / 100,
            10);

        PChangeOpenTicket(
            [calcDecimal.mul(2480) / 10000,
             calcDecimal.mul(780) / 10000,
             calcDecimal.mul(800) / 10000],
            [calcDecimal.mul(25) / 10,
             calcDecimal.mul(5),
             calcDecimal.mul(100)],
            calcDecimal / 70000000,
            500);

        PChangeTime(
            12 hours,
            10 hours,
            30 seconds,
            72 hours);

        PChangeRatio(
            1 finney,
            [0,
             calcDecimal.mul(2) / 100,
             calcDecimal.mul(5) / 100,
             calcDecimal.mul(10) / 100,
             calcDecimal.mul(20) / 100,
             calcDecimal.mul(30) / 100],
            [calcDecimal.mul(50) / 100,
             calcDecimal.mul(25) / 100,
             calcDecimal.mul(125) / 1000,
             calcDecimal.mul(75) / 1000,
             calcDecimal.mul(50) / 1000]);
    }
    
    function initNewRound()
            private{
        if(sInfo.rndIdx == 0){
            initFirstRound();
        } else {
            Help.initSameParamWithLast(rInfo[sInfo.rndIdx], rInfo[sInfo.rndIdx.add(1)]);
        }
        return;
    }

    function startNewRound()
            private{
        uint256 rndIdx = sInfo.rndIdx;
        uint256 newIdx = rndIdx.add(1);
        DataSets.RoundInfo storage _newRInfo = rInfo[newIdx];
        
        require((rndIdx == 0 && sInfo.finishSetSecretHash == 1) || rInfo[rndIdx].rFlag.terminate, "the last round has running");
        Help.checkStartNewRound(sInfo, _newRInfo);
        
        if (rndIdx > 0){
            _newRInfo.rPool.discountPool = rInfo[rndIdx].rPool.nextDiscountPool;
        }

        sInfo.rndIdx = newIdx;
    }
}
    
