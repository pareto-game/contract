pragma solidity ^0.4.25;

import "./DataSets.sol";
import "./Util.sol";
import "./seroInterface.sol";

library Help{
    using SafeMath for uint256;

    uint256 constant calcDecimal = 1e18;

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

    //////////////////////////////////////// open ticket
    //////////////////// lock
    
    function checkUpdateLockOpenTicket(
        DataSets.SystemInfo storage sInfo,
        DataSets.RoundInfo storage _rInfo)
            public{
        
        DataSets.SystemRndOpenTicket storage _rOpenTicket = _rInfo.rOpenTicket;

        require(!_rInfo.rFlag.terminate, "already terminate");
        require(now >= _rInfo.rTime.startTime, "must start");
        
        require(_rOpenTicket.step == 0, "step error");
        require(_rOpenTicket.penddingTickets >= _rInfo.pOpenTicket.ticketOpenMin, "open ticket not enough");

        _rOpenTicket.nowOpenHash = keccak256(abi.encodePacked(
            _rOpenTicket.nowOpenHash,
            now,
            block.coinbase,
            block.number));
        
        _rOpenTicket.step = 1;

        emit LogLockOpenTicket(
            sInfo.rndIdx,
            _rOpenTicket.nowOpenTicketCounterID,
            _rOpenTicket.penddingTickets);
    }

    //////////////////// open award
    
    function checkOpenTicketKey(
        string memory key,
        bytes32 newHash,
        DataSets.SystemInfo storage sInfo)
            public{
        
        require(newHash != '', "new hash error");

        // check key
        bytes32 keyHash = keccak256(abi.encodePacked(key));
        require(keyHash == sInfo.openSecretHashs[sInfo.nowOpenHashID], "key is error");
        sInfo.openSecretHashs[sInfo.nowOpenHashID] = newHash;
        sInfo.nowOpenHashID = sInfo.nowOpenHashID.add(1) % sInfo.openSecretHashs.length;
    }

    function computeAwardNum(
        string memory key,
        DataSets.SystemInfo storage sInfo,
        DataSets.RoundInfo storage _rInfo)
            public{

        DataSets.SystemRndParamOpenTicket storage _pOpenTicket = _rInfo.pOpenTicket;
        DataSets.SystemRndOpenTicket storage _rOpenTicket = _rInfo.rOpenTicket;

        require(_rOpenTicket.step == 1, "step should lock");

        bytes32 nowOpenHash = keccak256(abi.encodePacked(
            _rOpenTicket.nowOpenHash,
            key));

        uint256 exp = computeTicketExp(_rInfo);
        uint256 awardTotal;
        uint256 basePrice = newTicketPrice(_rInfo);
        for(uint256 i = 0; i < _rOpenTicket.nowAwardNum.length; i++){
            awardTotal = awardTotal.add(computeOneAwardNum(
                exp,
                basePrice,
                i,
                nowOpenHash,
                _pOpenTicket,
                _rOpenTicket));
            
            nowOpenHash = keccak256(abi.encodePacked(nowOpenHash, awardTotal));
        }

        // compute ur
        uint256 num = computeHit(
            _pOpenTicket.urRatio.mul(_rOpenTicket.penddingTickets),
            nowOpenHash);
        if (num > 0){
            _rOpenTicket.nowURAwardNum = 1;
        }

        _rOpenTicket.nowOpenHash = keccak256(abi.encodePacked(
            nowOpenHash,
            num));

        // update award pool
        _rInfo.rPool.awardPool = _rInfo.rPool.awardPool.sub(awardTotal);
        
        // update k
        uint256 diffk = 0;
        if(awardTotal > exp){
            diffk = awardTotal.sub(exp);
            if (diffk > _rOpenTicket.k){
                _rOpenTicket.k = 0;
            } else {
                _rOpenTicket.k = _rOpenTicket.k.sub(diffk);
            }
        } else {
            diffk = exp.sub(awardTotal);
            _rOpenTicket.k = _rOpenTicket.k.add(diffk);
        }
        
        // update fk;
        _rOpenTicket.fk = _rOpenTicket.k.mul(calcDecimal).sqrt() / 1000;

        _rOpenTicket.step = 2;

        // snap mask
        DataSets.SystemRndTicket storage _rTicket = _rInfo.rTicket;
        _rOpenTicket.maskSnap[_rOpenTicket.nowOpenTicketCounterID] = _rTicket.mask;

        // sub opened tickets
        _rTicket.tickets = _rTicket.tickets.sub(_rOpenTicket.penddingTickets);

        emit LogFinishComputeOpenTicket(
            sInfo.rndIdx,
            _rOpenTicket.nowOpenTicketCounterID,
            awardTotal,
            basePrice);

        return;
    }

    function quicksort(
        DataSets.PersonAwardRecord[] memory awardPerson,
        uint256 left,
        uint256 right)
            private{
        if(left >= right) return;
        
        uint256 midIdx = left + (right - left) / 2;
        uint256 middle = awardPerson[midIdx].ticketPos;

        (awardPerson[right], awardPerson[midIdx]) = (awardPerson[midIdx], awardPerson[right]);
        
        uint256 i = left;
        uint256 j = right - 1;
        bool goout = false;
        while(i <= j){
            while(awardPerson[i].ticketPos < middle) i++;

            while(awardPerson[j].ticketPos >= middle && j >= left){
                if (j > 0) {
                    j--;
                    continue;
                } else {
                    goout = true;
                    break;
                }
            }

            if(goout){
                break;
            }
            
            if(i < j){
                (awardPerson[i], awardPerson[j]) = (awardPerson[j], awardPerson[i]);
                i++;
                j--;
            }
        }

        if(i != right){
            (awardPerson[right], awardPerson[i]) = (awardPerson[i], awardPerson[right]);
        }

        if(i > left + 1){
            quicksort(awardPerson, left, i-1);
        }

        if (i + 1 < right){
            quicksort(awardPerson, i + 1, right);
        }
    }

    function publishAward(
        uint256 num,
        DataSets.SystemInfo storage sInfo,
        DataSets.RoundInfo storage _rInfo)
            public{
        
        require(num > 0, "num zero");
        
        DataSets.SystemRndOpenTicket storage _rOpenTicket = _rInfo.rOpenTicket;

        require(_rOpenTicket.step == 2, "step error");

        DataSets.PersonAwardRecord[] memory awardPerson = new DataSets.PersonAwardRecord[](num);
        uint256 idx = 0;
        bytes32 nowOpenHash = _rOpenTicket.nowOpenHash;
        uint256 tmp;

        // ur
        if( _rOpenTicket.nowURAwardNum == 1 && !_rInfo.rFlag.urAwardEnd){
            tmp = computePosition(_rOpenTicket.penddingTickets, nowOpenHash);
            nowOpenHash = keccak256(abi.encodePacked(nowOpenHash, tmp));

            awardPerson[idx].ticketPos = tmp;
            awardPerson[idx].awardLevel = 3;
            idx++;

            endRound(true, sInfo, _rInfo);
        }

        uint256 i = 0;
        uint256 j = 0;
        bool clean;
        for(; idx < num; ){
            if (i == _rOpenTicket.nowAwardNum.length){
                clean = true;
                break;
            }
            if( j == _rOpenTicket.nowAwardNum[i]){
                if ( j != 0){
                    _rOpenTicket.nowAwardNum[i] = 0;
                    j = 0;
                }
                i++;
                continue;
            }

            tmp = computePosition(_rOpenTicket.penddingTickets, nowOpenHash);
            nowOpenHash = keccak256(abi.encodePacked(nowOpenHash, tmp));

            awardPerson[idx].ticketPos = tmp;
            awardPerson[idx].awardLevel = i;
            idx++;
            j++;
        }

        if( j > 0){
            _rOpenTicket.nowAwardNum[i] = _rOpenTicket.nowAwardNum[i].sub(j);
        }

        if(idx > 0){
            // publish award
            // sort
            quicksort(awardPerson, 0, idx - 1);
        
            // update nowOpenHash
            _rOpenTicket.nowOpenHash = keccak256(abi.encodePacked(
                nowOpenHash,
                num));

            // real publish
            realPublishAward(
                idx,
                awardPerson,
                _rOpenTicket,
                sInfo,
                _rInfo);
        }
        
        if (clean){
            cleanNowOpenTicket(sInfo, _rInfo);
        }
    }

    function realPublishAward(
        uint256 idx,
        DataSets.PersonAwardRecord[] memory awardPerson,
        DataSets.SystemRndOpenTicket storage _rOpenTicket,
        DataSets.SystemInfo storage sInfo,
        DataSets.RoundInfo storage _rInfo)
            private{

        uint256 j = 0;
        uint256 i = 1;
        uint256 tmp = 0;
        uint256[4] memory awardNum;
        for(; j < idx && i < _rOpenTicket.newWaitForOpenID; i++){
            // find win person
            tmp = tmp.add(_rOpenTicket.waitForOpen[i].tickets);
            if(tmp <= awardPerson[j].ticketPos){ // this person no award
                continue;
            }

            // compute award num
            while(j < idx && tmp > awardPerson[j].ticketPos){
                awardNum[awardPerson[j].awardLevel]++;
                j++;
            }

            // publish award
            DataSets.PlayerBaseInfo storage pBaseInfo = sInfo.playerBaseInfo[_rOpenTicket.waitForOpen[i].pid];
            // publish ur
            if( awardNum[3] > 0){
                updateLastPerson(
                    sInfo.playerRndInfo[pBaseInfo.ID][sInfo.rndIdx],
                    _rInfo,
                    sInfo,
                    pBaseInfo.ID,
                    0);
                emit LogOpenTicketWin(
                    sInfo.rndIdx,
                    _rOpenTicket.nowOpenTicketCounterID,
                    pBaseInfo.addr,
                    1,
                    0,
                    now,
                    3,
                    pBaseInfo.name);
                awardNum[3] = 0;
            }
            // publish normal award
            for(uint256 k = 0; k < 3; k++){
                if (awardNum[k] == 0){
                    continue;
                }

                uint256 awardEth = _rOpenTicket.award[k].mul(awardNum[k]);
                playerAddWin(pBaseInfo, awardEth);
                _rOpenTicket.totalWinEth = _rOpenTicket.totalWinEth.add(awardEth);
                _rOpenTicket.totalAwardNum[k] = _rOpenTicket.totalAwardNum[k].add(awardNum[k]);

                emit LogOpenTicketWin(
                    sInfo.rndIdx,
                    _rOpenTicket.nowOpenTicketCounterID,
                    pBaseInfo.addr,
                    awardNum[k],
                    _rOpenTicket.award[k],
                    now,
                    k,
                    pBaseInfo.name);

                awardNum[k] = 0;
            }
        }
    }
        

    function cleanNowOpenTicket(
        DataSets.SystemInfo storage sInfo,
        DataSets.RoundInfo storage _rInfo)
            public{
        DataSets.SystemRndOpenTicket storage _rOpenTicket = _rInfo.rOpenTicket;
        _rOpenTicket.nowOpenTicketCounterID = _rOpenTicket.nowOpenTicketCounterID.add(1);
        _rOpenTicket.penddingTickets = 0;
        _rOpenTicket.nowOpenHash = sInfo.openSecretHashs[sInfo.nowOpenHashID];
        _rOpenTicket.newWaitForOpenID = 1;
        _rOpenTicket.step = 0;

        for( uint256 i = 0; i < _rOpenTicket._exp.length; i++){
            _rOpenTicket.award[i] = 0;
            _rOpenTicket._probability[i] = 0;
            _rOpenTicket._exp[i] = 0;
        }
    }

    // exp = price * factor * num * p
    // award num = (num * p) % 1
    function computeOneAwardNum(
        uint256 exp,
        uint256 basePrice,
        uint256 i,
        bytes32 nowOpenHash,
        DataSets.SystemRndParamOpenTicket storage _pOpenTicket,
        DataSets.SystemRndOpenTicket storage _rOpenTicket)
            private
            returns(uint256 awardTotal){

        uint256 nowExp = exp.mul(_pOpenTicket.exp[i]) / calcDecimal;
        uint256 nowAward = basePrice.mul(_pOpenTicket.factor[i]) / calcDecimal;

        uint256 probability = computeTicketProbability(
            nowExp,
            nowAward);
        uint256 rProbability = probability;
        
        uint256 ticket = _rOpenTicket.penddingTickets;

        if (probability > ticket.mul(calcDecimal)){
            probability = ticket.mul(calcDecimal);
        }

        uint256 num;
        if(probability > calcDecimal){
            num = num.add(probability / calcDecimal);
            probability %= calcDecimal;
        }
        
        if (probability > 0){
            num = num.add(
                computeHit(
                    probability,
                    nowOpenHash));
        }

        if(num > 0){
            _rOpenTicket.nowAwardNum[i] = num;
            _rOpenTicket.award[i] = nowAward;
            awardTotal = awardTotal.add(nowAward.mul(num));
        }
        _rOpenTicket._probability[i] = rProbability;
        _rOpenTicket._exp[i] = nowExp;

        return;
    }

    // exp = S(n+m) - S(n)
    function computeTicketExp(
        DataSets.RoundInfo storage _rInfo)
            private
            view
            returns (uint256){

        DataSets.SystemRndOpenTicket storage _rOpenTicket = _rInfo.rOpenTicket;
        uint256 m = _rOpenTicket.penddingTickets;
        uint256 fk = _rOpenTicket.fk;

        uint256 totalTickets = _rInfo.rTicket.tickets;
        uint256 n = totalTickets.sub(m);

        DataSets.SystemRndParamPrice storage _pPrice = _rInfo.pPrice;
        uint256 a = _pPrice.a;
        uint256 b = _pPrice.b;

        // (m(b+fk)+am(2n+m-1)/2)q
        uint256 result = b.add(fk).mul(m);

        uint256 tmp = n.mul(2).add(m).sub(1);
        tmp = tmp.mul(m).mul(a) / 2;
        
        result = result.add(tmp);
        result = result.mul(_rInfo.pAssign.tAward) / calcDecimal;

        return result;
    }

    // num * p = exp / award
    function computeTicketProbability(
        uint256 exp,
        uint256 award)
            private
            pure
            returns(uint256 p){
        require(award > 0, "compute award probability error");
        return exp.mul(calcDecimal) / award;
    }

    function computeHit(
        uint256 probability,
        bytes32 hash)
            private
            pure
            returns(uint256){

        if(probability == 0){
            return 0;
        }

        if(probability >= calcDecimal){
            return 1;
        }
        
        uint256 hashNum = uint256(hash);
        hashNum = hashNum % calcDecimal;
        if(hashNum < probability){
            return 1;
        }

        return 0;
    }

    function computePosition(
        uint256 tickets,
        bytes32 hash)
            private
            pure
            returns(uint256){

        uint256 result = uint256(hash);
        return result % tickets;
    }

    //////////////////////////////////////// time
    function timeEnd(
        DataSets.RoundInfo storage _rInfo)
            public
            view
            returns (bool){

        if (now < _rInfo.rTime.endTime){
            return false;
        }
        
        if (_rInfo.rTicket.eth == 0){
            return false;
        }

        return true;
    }

    function updateEndTime(
        uint256 tickets,
        DataSets.RoundInfo storage _rInfo)
            private{
        DataSets.SystemRndTime storage _rTime = _rInfo.rTime;
        DataSets.SystemRndParamTime storage _pTime = _rInfo.pTime;
        
        uint256 addTime = tickets.mul(_pTime.timeAdd);
        if (_rTime.endTime >= now){
            if(_rTime.endTime.add(addTime).sub(now) > _pTime.timeMax){
                _rTime.endTime = now.add(_pTime.timeMax);
            }else{
                _rTime.endTime = _rTime.endTime.add(addTime);
            }
            return;
        }

        if(addTime > _pTime.timeMax){
            _rTime.endTime = now.add(_pTime.timeMax);
        } else{
            _rTime.endTime = now.add(addTime);
        }
    }

    //////////////////////////////////////// logic func

    function checkStartNewRound(
        DataSets.SystemInfo storage sInfo,
        DataSets.RoundInfo storage _rInfo)
            public{
        require(_rInfo.pPrice.a > 0 && _rInfo.pPrice.b > 0, "param error");
        require(_rInfo.pPrice.b.mul(2) > _rInfo.pPrice.a, "should: 2b > a");
        require(_rInfo.pProtect.secret != '', "no protect secretKey");

        DataSets.SystemRndParamAssign storage _pAssign = _rInfo.pAssign;
        require(_pAssign.tAff.add(_pAssign.tShare).add(_pAssign.tAward) < calcDecimal, "assign ticket percent error");
        require(_pAssign.aBigWin.add(_pAssign.aOtherWin).add(_pAssign.aDiscount) < calcDecimal, "assign award percent error");
        require(_pAssign.lastPersonNum > 0, "last person num error");
        
        DataSets.SystemRndParamOpenTicket storage _pOpenTicket = _rInfo.pOpenTicket;
        for(uint256 i = 0; i < _pOpenTicket.exp.length; i++){
            require(_pOpenTicket.exp[i] > 0 && _pOpenTicket.exp[i] < calcDecimal, "exp error");
            require(_pOpenTicket.factor[i] > 0, "factor error");  
        }
        require(_pOpenTicket.urRatio > 0, "ur ratio, error");
        require(_pOpenTicket.ticketOpenMin > 0, "open ticket min  error");

        DataSets.SystemRndParamTime storage _pTime = _rInfo.pTime;
        require(_pTime.timeMax > _pTime.timeInit, "time init error");
        require(_pTime.timeInit > _pTime.timeAdd, "time init too small");
        require(_pTime.timeAdd > 0, "time add error");

        DataSets.SystemRndParamRatio storage _pRatio = _rInfo.pRatio;
        for(i = 0; i < _pRatio.discountLevel.length; i++){
            require(_pRatio.discountLevel[i] < (calcDecimal.mul(50) / 100), "too large discount");
        }
        uint256 affTotal = 0;
        for(i = 0; i < _pRatio.affRatio.length; i++){
            affTotal = affTotal.add(_pRatio.affRatio[i]);
        }
        require(affTotal <= calcDecimal, "affTotalRatio error");

        // update system info
        DataSets.SystemRndTime storage _rTime = _rInfo.rTime;
        _rTime.startTime = now.add(_pTime.startTimeInterval);
        _rTime.endTime = _rTime.startTime.add(_pTime.timeInit);

        DataSets.SystemRndOpenTicket storage _rOpenTicket = _rInfo.rOpenTicket;
        _rOpenTicket.nowOpenHash = sInfo.openSecretHashs[sInfo.nowOpenHashID];
        _rOpenTicket.nowOpenTicketCounterID = 1;
        _rOpenTicket.waitForOpen.length = 1;
        _rOpenTicket.newWaitForOpenID = 1;
    }

    function buyTickets(
        DataSets.PlayerBaseInfo storage pBaseInfo,
        DataSets.PlayerRndInfo storage pRndInfo,
        uint256 payEth,
        uint256 maxTickets, 
        bytes32 affName,
        DataSets.RoundInfo storage _rInfo,
        DataSets.SystemInfo storage sInfo)
            public{

        uint256 tickets;
        uint256 needEth;
        uint256 discountEth;
        
        (tickets,
         needEth,
         payEth,
         discountEth) = prepareBuyTickets(
             pBaseInfo,
             pRndInfo,
             payEth,
             maxTickets,
             _rInfo);

        require(tickets != 0, "can't buy 1 ticket");

        realBuy(
            pBaseInfo,
            pRndInfo,
            needEth,
            discountEth,
            payEth,
            tickets,
            affName,
            _rInfo,
            sInfo);
    }

    function reBuyOther(
        uint256 payEth,
        DataSets.PlayerRndInfo storage pRndInfo,
        DataSets.PlayerBaseInfo storage pBaseInfo,
        DataSets.RoundInfo storage _rInfo,
        DataSets.SystemInfo storage sInfo)
            public{
        
        require(pRndInfo.enableAutoBuy, "this user doesn't enable auto buy");
        require(pRndInfo.lastPersonCounter == 0, "this user is last person");

        uint256 tickets = pRndInfo.autoBuyTicketNum;
        
        buyTickets(
            pBaseInfo,
            pRndInfo,
            payEth,
            tickets,
            '',
            _rInfo,
            sInfo);
    }

    function prepareBuyTickets(
        DataSets.PlayerBaseInfo storage pBaseInfo,
        DataSets.PlayerRndInfo storage pRndInfo,
        uint256 maxPayEth,
        uint256 maxTickets, 
        DataSets.RoundInfo storage _rInfo)
            public
            returns(
                uint256 tickets,
                uint256 needEth,
                uint256 payEth,
                uint256 discountEth){

        require(maxTickets > 0 && maxPayEth > 0, "[ticket num]/[pay eth] error");

        payEth = maxPayEth;
        
        // compute discount
        discountEth = computeDiscount(_rInfo, payEth, pRndInfo.level);
        uint256 totalEth;
        DataSets.SystemRndTicket storage _rTicket = _rInfo.rTicket;
        DataSets.SystemRndParamICO storage _pICO = _rInfo.pICO;
        
        // ICO phase
        if (_rTicket.eth < _pICO.totalEth &&
            pRndInfo.eth.add(payEth).add(discountEth) > _pICO.perAddrEth){
            totalEth = _pICO.perAddrEth.sub(pRndInfo.eth);
            discountEth = computeDiscountByTotal(_rInfo, totalEth, pRndInfo.level);
            payEth = totalEth.sub(discountEth);
        } else{
            totalEth = payEth.add(discountEth);
        }

        // compute ticket num, and actual pay eth
        (tickets, needEth) = computeTickets(_rInfo, totalEth, maxTickets);

        require(totalEth >= needEth, "compute need eth error");
        if (totalEth > needEth){
            discountEth = computeDiscountByTotal(_rInfo, needEth, pRndInfo.level);
            payEth = needEth.sub(discountEth);
        }

        if (maxPayEth.sub(payEth) > 0){
            pBaseInfo.avaiEth = pBaseInfo.avaiEth.add(maxPayEth.sub(payEth));
        }

        return;
    }

    function realBuy(
        DataSets.PlayerBaseInfo storage pBaseInfo,
        DataSets.PlayerRndInfo storage pRndInfo,
        uint256 needEth,
        uint256 discountEth,
        uint256 payEth,
        uint256 tickets, 
        bytes32 affName,
        DataSets.RoundInfo storage _rInfo,
        DataSets.SystemInfo storage sInfo)
            public{
        
        DataSets.SystemRndTicket storage _rTicket = _rInfo.rTicket;        
        
        // -------------------- real buy
        // update player
        pRndInfo.eth = pRndInfo.eth.add(needEth);
        pRndInfo.payEth = pRndInfo.payEth.add(payEth);
        pRndInfo.nowTickets = pRndInfo.nowTickets.add(tickets);
        pRndInfo.totalTickets = pRndInfo.totalTickets.add(tickets);
        pRndInfo.mask = pRndInfo.mask.add(_rTicket.mask.mul(tickets));

        // record system info
        _rTicket.tickets = _rTicket.tickets.add(tickets);
        _rTicket.totalTickets = _rTicket.totalTickets.add(tickets);
        _rTicket.eth = _rTicket.eth.add(needEth);
        _rTicket.newBuyID = _rTicket.newBuyID.add(1);
        _rInfo.rPool.discountPool = _rInfo.rPool.discountPool.sub(discountEth);
        
        assignTicketEth(pBaseInfo, _rInfo, sInfo, affName, needEth);
        updateEndTime(tickets, _rInfo);
        updateLastPerson(pRndInfo, _rInfo, sInfo, pBaseInfo.ID, tickets);

        emit LogBuyTicket(
            sInfo.rndIdx,
            pBaseInfo.addr,
            pBaseInfo.name,
            tickets,
            needEth,
            now,
            _rTicket.newBuyID);
    }
    
    function checkProtectKey(
        bytes memory key,
        DataSets.RoundInfo storage _rInfo)
            public
            view{

        DataSets.SystemRndParamProtect storage _pProtect = _rInfo.pProtect;
        if (now.sub(_rInfo.rTime.startTime) > _pProtect.duration){
            return;
        }

        bytes32 keyHash = keccak256(abi.encodePacked(key));
        require(keyHash == _pProtect.secret, "key is error");
    }

    function updateLastPerson(
        DataSets.PlayerRndInfo storage pRndInfo,
        DataSets.RoundInfo storage _rInfo,
        DataSets.SystemInfo storage sInfo,
        uint256 nowPid,
        uint256 tickets)
            private{
        DataSets.LastPersonBuyInfo memory lastPInfo;
        lastPInfo.pid = nowPid;
        lastPInfo.tickets = tickets;
        pRndInfo.lastPersonCounter = pRndInfo.lastPersonCounter.add(1);

        DataSets.SystemRndTicket storage _rTicket = _rInfo.rTicket;

        // update 
        uint256 idx = _rTicket.lastQueueFirst;
        DataSets.LastPersonBuyInfo[] storage lastPersonQueue = _rTicket.lastPersonQueue;
        
        if (lastPersonQueue.length < _rInfo.pAssign.lastPersonNum){
            if (lastPersonQueue.length > 0){
                idx += 1;
            }
            lastPersonQueue.push(lastPInfo);
            _rTicket.lastQueueFirst = idx;
            return;
        }
        
        if (idx == _rInfo.pAssign.lastPersonNum - 1){
            idx = 0;
        } else {
            idx += 1;
        }

        DataSets.LastPersonBuyInfo storage oldPerson = lastPersonQueue[idx];

        uint256 oldID = oldPerson.pid;
        DataSets.PlayerRndInfo storage oldPRndInfo = sInfo.playerRndInfo[oldID][sInfo.rndIdx];
        require(oldPRndInfo.lastPersonCounter > 0, "last counter error");
        oldPRndInfo.lastPersonCounter -= 1;

        lastPersonQueue[idx] = lastPInfo;

        _rTicket.lastQueueFirst = idx;

        emit LogReplaceLastPerson(sInfo.rndIdx, oldID, nowPid);
    }

    //////////////////////////////////////// round func
    function endTerminateRound(
        bool urEnded,
        DataSets.SystemInfo storage sInfo,
        DataSets.RoundInfo storage _rInfo)
            public{
        endRound(urEnded, sInfo, _rInfo);
        terminateRound(sInfo, _rInfo);
    }
    
    function endRound(
        bool urEnded,
        DataSets.SystemInfo storage sInfo,
        DataSets.RoundInfo storage _rInfo)
            public{

        DataSets.SystemRndFlag storage _rFlag = _rInfo.rFlag;
        _rFlag.ended = true;
        if(urEnded){
            _rFlag.urAwardEnd = true;
            _rInfo.rTime.endTime = now;
        }

        emit LogFlag(
            sInfo.rndIdx,
            _rFlag.ended,
            _rFlag.terminate,
            _rFlag.urAwardEnd);
    }

    function terminateRound(
        DataSets.SystemInfo storage sInfo,        
        DataSets.RoundInfo storage _rInfo)
            public{
        
        require(!_rInfo.rFlag.terminate, "already terminate");
        
        // check
        DataSets.SystemRndOpenTicket storage _rOpenTicket = _rInfo.rOpenTicket;
        DataSets.SystemRndFlag storage _rFlag = _rInfo.rFlag;
        
        if(!_rFlag.ended ||
           _rOpenTicket.penddingTickets >= _rInfo.pOpenTicket.ticketOpenMin ||
           _rOpenTicket.step != 0){
            return;
        }
        
        _rFlag.terminate = true;
        assignAwardEth(sInfo, _rInfo);
        emit LogFlag(
            sInfo.rndIdx,
            _rFlag.ended,
            _rFlag.terminate,
            _rFlag.urAwardEnd);
    }

    function assignAwardEth(
        DataSets.SystemInfo storage sInfo,
        DataSets.RoundInfo storage _rInfo)
            private{
        
        DataSets.SystemRndPool storage _rPool = _rInfo.rPool;
        uint256 totalAward = _rPool.awardPool.add(_rPool.discountPool);
        uint256 remainEth = totalAward;

        uint256 lastIdx = _rInfo.rTicket.lastQueueFirst;
        DataSets.LastPersonBuyInfo[] storage lastPersonQ = _rInfo.rTicket.lastPersonQueue;
        DataSets.SystemRndParamAssign storage _pAssign = _rInfo.pAssign;
        
        // assign biggest win
        uint256 pid = lastPersonQ[lastIdx].pid;
        DataSets.PlayerBaseInfo storage pBaseInfo = sInfo.playerBaseInfo[pid];
        uint256 nowAssignEth = totalAward.mul(_pAssign.aBigWin) / calcDecimal;
        playerAddWin(pBaseInfo, nowAssignEth);
        remainEth = remainEth.sub(nowAssignEth);

        // assign other people
        uint256 personNum = lastPersonQ.length;
        if(personNum > 1){
            nowAssignEth = totalAward.mul(_pAssign.aOtherWin) / calcDecimal;
            
            uint256 totalTickets;
            for(uint256 i = 0; i < personNum - 1; i++){
                if(lastIdx == 0){
                    lastIdx = personNum - 1;
                } else{
                    lastIdx -= 1;
                }

                if(lastPersonQ[lastIdx].pid == 0){
                    break;
                }

                totalTickets.add(lastPersonQ[lastIdx].tickets);
            }

            uint256 personAssignEth;
            lastIdx = _rInfo.rTicket.lastQueueFirst;
            for(i = 0; totalTickets > 0 && i < personNum - 1; i++){
                if(lastIdx == 0){
                    lastIdx = personNum - 1;
                } else{
                    lastIdx -= 1;
                }
                
                pid = lastPersonQ[lastIdx].pid;

                if(pid == 0){
                    break;
                }

                pBaseInfo = sInfo.playerBaseInfo[pid];
                personAssignEth = nowAssignEth.mul(lastPersonQ[lastIdx].tickets) / totalTickets;
                playerAddWin(pBaseInfo, personAssignEth);
                remainEth = remainEth.sub(personAssignEth);
            }
        }

        // to next discount pool
        nowAssignEth = totalAward.mul(_pAssign.aDiscount) / calcDecimal;
        _rPool.nextDiscountPool = nowAssignEth;
        remainEth = remainEth.sub(nowAssignEth);

        // to dev
        if(remainEth > 0){
            // sInfo.devAddr.transfer(remainEth);
            devAdd(sInfo, remainEth);
        }
    }

    //////////////////////////////////////// player func

    function devAdd(
        DataSets.SystemInfo storage sInfo,
        uint256 devEth)
            internal{

        DataSets.PlayerBaseInfo storage pBaseInfo = sInfo.playerBaseInfo[sInfo.devID];
        pBaseInfo.avaiEth = pBaseInfo.avaiEth.add(devEth);
    }
    function playerAddWin(
        DataSets.PlayerBaseInfo storage pBaseInfo,
        uint256 win)
            public{
        pBaseInfo.winEth = pBaseInfo.winEth.add(win);
        pBaseInfo.avaiEth = pBaseInfo.avaiEth.add(win);
    }

    function playerAddAff(
        DataSets.PlayerBaseInfo storage pBaseInfo,
        uint256 aff)
            public{
        pBaseInfo.affEth = pBaseInfo.affEth.add(aff);
        pBaseInfo.avaiEth = pBaseInfo.avaiEth.add(aff);
    }

    function playerAddShared(
        DataSets.PlayerBaseInfo storage pBaseInfo,
        uint256 shared)
            public{
        pBaseInfo.sharedEth = pBaseInfo.sharedEth.add(shared);
        pBaseInfo.avaiEth = pBaseInfo.avaiEth.add(shared);
    }

    function updateMask(
        DataSets.RoundInfo storage _rInfo,
        DataSets.PlayerBaseInfo storage pBaseInfo,
        DataSets.PlayerRndInfo storage pRndInfo)
            public{

        (uint256 earnEth, uint256 subMask, uint256 subTickets, bool cleanOpenTicket) = getUnmaskEth(_rInfo, pRndInfo);

        if(cleanOpenTicket){
            pRndInfo.nowTickets = pRndInfo.nowTickets.sub(subTickets);
            pRndInfo.penddingTickets = 0;
            pRndInfo.waitForOpenID = 0;
            pRndInfo.lastOpenTicketCounterID = 0;
        }
        
        pRndInfo.mask = pRndInfo.mask.add(earnEth).sub(subMask);
        playerAddShared(pBaseInfo, earnEth);
    }

    function getUnmaskEth(
        DataSets.RoundInfo storage _rInfo,
        DataSets.PlayerRndInfo storage pRndInfo)
            public
            view
            returns(
                uint256 earnEth,
                uint256 subMask,
                uint256 subTickets,
                bool cleanOpenTicket){

        DataSets.SystemRndOpenTicket storage _rOpenTicket = _rInfo.rOpenTicket;
        DataSets.SystemRndTicket storage _rTicket = _rInfo.rTicket;        

        if(pRndInfo.lastOpenTicketCounterID != 0 &&
           (pRndInfo.lastOpenTicketCounterID != _rOpenTicket.nowOpenTicketCounterID ||
            _rOpenTicket.step >= 2)){
            
            uint256 perTicketMask = _rOpenTicket.maskSnap[pRndInfo.lastOpenTicketCounterID];
            earnEth = pRndInfo.nowTickets.mul(perTicketMask).sub(pRndInfo.mask);

            subMask = pRndInfo.penddingTickets.mul(perTicketMask);

            subTickets = pRndInfo.penddingTickets;

            cleanOpenTicket = true;
        }

        uint256 remainTickets = pRndInfo.nowTickets.sub(subTickets);
        uint256 nowMask = pRndInfo.mask.add(earnEth).sub(subMask);
        earnEth = earnEth.add(remainTickets.mul(_rTicket.mask).sub(nowMask));

        return;
    }

    function getNowRndLevel(
        DataSets.PlayerBaseInfo storage pBaseInfo,
        DataSets.PlayerRndInfo storage pRndInfo,
        DataSets.SystemInfo storage sInfo)
            view
            public
            returns(uint8 level){

        uint256 lastRndIdx = pBaseInfo.lastRoundID;
        if (lastRndIdx == sInfo.rndIdx){
            return pRndInfo.level;
        } else if (lastRndIdx.add(1) != sInfo.rndIdx){
            return 0;
        }

        DataSets.PlayerRndInfo storage lastPRndInfo = sInfo.playerRndInfo[pBaseInfo.ID][lastRndIdx];        

        if (lastPRndInfo.totalTickets > 1000000){
            return 5;
        } else if (lastPRndInfo.totalTickets > 100000){
            return 4;
        } else if (lastPRndInfo.totalTickets > 10000){
            return 3;
        } else if (lastPRndInfo.totalTickets > 1000){
            return 2;
        } else if (lastPRndInfo.totalTickets > 100){
            return 1;
        } 
        return 0;
    }

    //////////////////////////////////////// assign
    function assignTicketEth(
        DataSets.PlayerBaseInfo storage pBaseInfo,
        DataSets.RoundInfo storage _rInfo,
        DataSets.SystemInfo storage sInfo,
        bytes32 affName,
        uint256 totalEth)
            private{

        uint256 remainEth = totalEth;
        uint256 nowAssignEth;

        DataSets.SystemRndParamAssign storage _pAssign = _rInfo.pAssign;
        DataSets.SystemRndTicket storage _rTicket = _rInfo.rTicket;
        
        // award pool
        nowAssignEth = totalEth.mul(_pAssign.tAward) / calcDecimal;
        _rInfo.rPool.awardPool = _rInfo.rPool.awardPool.add(nowAssignEth);
        remainEth = remainEth.sub(nowAssignEth);

        // aff
        nowAssignEth = totalEth.mul(_pAssign.tAff) / calcDecimal;
        remainEth = remainEth.add(
            assignAffEth(
                pBaseInfo,
                _rInfo,
                sInfo,
                affName,
                nowAssignEth));
        remainEth = remainEth.sub(nowAssignEth);
        _rTicket.totalAffEth = _rTicket.totalAffEth.add(nowAssignEth);

        // ticket assign mask
        nowAssignEth = totalEth.mul(_pAssign.tShare) / calcDecimal;
        _rTicket.mask = _rTicket.mask.add(nowAssignEth / _rTicket.tickets);
        remainEth = remainEth.sub(nowAssignEth);
        _rTicket.totalSharedEth = _rTicket.totalSharedEth.add(nowAssignEth);

        if(remainEth > 0){
            devAdd(sInfo, remainEth);
            // sInfo.devAddr.transfer(remainEth);
        }
    }

    function assignAffEth(
        DataSets.PlayerBaseInfo storage pBaseInfo,
        DataSets.RoundInfo storage _rInfo,
        DataSets.SystemInfo storage sInfo,
        bytes32 affName,
        uint256 affEth)
            private
            returns (uint256 remainEth){

        remainEth = affEth;

        // get aff id
        uint256 parentAffID;
        if (affName != '' && affName != pBaseInfo.name){
            parentAffID = sInfo.playerAffNameIdx[affName];
        }

        bool updateLastAffID = true;
        if (parentAffID == 0 || parentAffID == pBaseInfo.ID){
            parentAffID = pBaseInfo.lastAffID;
            updateLastAffID = false;
        } 
        
        DataSets.SystemRndParamRatio storage _pRatio = _rInfo.pRatio;

        uint256 affID = parentAffID;
        uint256 nowAssignEth;
        for(uint256 i = 0; i < _pRatio.affRatio.length; i++){
            if(affID == 0){
                break;
            }
            
            if (affID == pBaseInfo.ID){
                updateLastAffID = false;
                break;
            }
            
            DataSets.PlayerBaseInfo storage affBaseInfo = sInfo.playerBaseInfo[affID];
            nowAssignEth = affEth.mul(_pRatio.affRatio[i]) / calcDecimal;

            playerAddAff(affBaseInfo, nowAssignEth);

            emit LogAff(
                sInfo.rndIdx,
                affBaseInfo.addr,
                affBaseInfo.name,
                now,
                nowAssignEth);
            
            remainEth = remainEth.sub(nowAssignEth);

            affID = affBaseInfo.lastAffID;
        }

        if (updateLastAffID){
            pBaseInfo.lastAffID = parentAffID;            
        }
        
        return remainEth;
    }

    //////////////////////////////////////// compute price, eth, ...
    function newTicketPrice(
        DataSets.RoundInfo storage _rInfo)
            public
            view
            returns (uint256){

        return _rInfo.pPrice.a.
                mul(_rInfo.rTicket.tickets).
                add(_rInfo.pPrice.b).
                add(_rInfo.rOpenTicket.fk);
    }

    function computeDiscount(
        DataSets.RoundInfo storage _rInfo,
        uint256 payEth,
        uint8 level)
            private
            view
            returns (uint256 discountEth){

        DataSets.SystemRndParamRatio storage _pRatio = _rInfo.pRatio;
        DataSets.SystemRndPool storage _rPool = _rInfo.rPool;

        require(level < _pRatio.discountLevel.length, "level error");

        discountEth = payEth.mul(_pRatio.discountLevel[level]) / calcDecimal;

        if (discountEth > _rPool.discountPool){
            discountEth = _rPool.discountPool;
        }
        
        return discountEth;
    }
    

    function computeDiscountByTotal(
        DataSets.RoundInfo storage _rInfo,
        uint256 totalEth,
        uint8 level)
            public
            view
            returns (uint256 discountEth){

        DataSets.SystemRndParamRatio storage _pRatio = _rInfo.pRatio;
        DataSets.SystemRndPool storage _rPool = _rInfo.rPool;

        require(level < _pRatio.discountLevel.length, "discount length error");

        uint256 discount = _pRatio.discountLevel[level];

        discountEth = (totalEth.mul(discount)) / (calcDecimal.add(discount));
        if (discountEth > _rPool.discountPool){
            discountEth = _rPool.discountPool;
        }

        return discountEth;
    }

    
    function computeTickets(
        DataSets.RoundInfo storage _rInfo,
        uint256 payEth,
        uint256 maxTickets)
            private
            view
            returns (uint256 tickets, uint256 needEth){
        
        tickets = computePayEthTickets(_rInfo, payEth);
        if (tickets > maxTickets){
            tickets = maxTickets;
        }

        needEth = computeTicketPayEth(_rInfo, tickets);
        return (tickets, needEth);
    }

    // tickets -> payeth
    function computeTicketPayEth(
        DataSets.RoundInfo storage _rInfo,
        uint256 tickets)
            public
            view
            returns (uint256 payEth){

        if (tickets == 0){
            return 0;
        }
        
        DataSets.SystemRndParamPrice storage _pPrice = _rInfo.pPrice;
        
        uint256 a = _pPrice.a;
        uint256 b = _pPrice.b;

        // m(b+a(n+(m-1)/2) + fk)
        payEth = tickets.mul(calcDecimal).sub(calcDecimal) / 2;
        payEth = payEth.add(_rInfo.rTicket.tickets.mul(calcDecimal)).mul(a) / calcDecimal;
        payEth = payEth.add(b).add(_rInfo.rOpenTicket.fk);
        payEth = payEth.mul(tickets);
        
        return payEth;
    }

    // payeth -> tickets
    // tickets use round off
    function computePayEthTickets(
        DataSets.RoundInfo storage _rInfo,
        uint256 payEth)
            public
            view
            returns (uint256 tickets){
        if(newTicketPrice(_rInfo) > payEth){
            return 0;
        }
        
        DataSets.SystemRndParamPrice storage _pPrice = _rInfo.pPrice;
        
        uint256 a = _pPrice.a;
        uint256 aSqrt = _pPrice.aSqrt;
        uint256 b = _pPrice.b;

        uint256 c = a / 2;
        c = _rInfo.rOpenTicket.fk.add(a.mul(_rInfo.rTicket.tickets)).add(b).sub(c);

        tickets = c.sq() / a;
        tickets = tickets.add(payEth.mul(2));
        tickets = tickets.mul(calcDecimal).sqrt();

        uint256 tmp = c.mul(calcDecimal) / aSqrt;

        tickets = tickets.sub(tmp).mul(calcDecimal) / aSqrt;
        return tickets / calcDecimal;
    }

    function initSameParamWithLast(
        DataSets.RoundInfo storage nowR,
        DataSets.RoundInfo storage nextR)
            public{
        nextR.pPrice = nowR.pPrice;
        nextR.pProtect = nowR.pProtect;
        nextR.pICO = nowR.pICO;
        nextR.pAssign = nowR.pAssign;
        nextR.pOpenTicket = nowR.pOpenTicket;
        nextR.pTime = nowR.pTime;
        nextR.pRatio = nowR.pRatio;
    }

    //////////////////////////////////////// register
    function registerName(
        string memory name,
        bytes32 affName,
        uint256 pid,
        uint256 payEth,
        DataSets.SystemInfo storage sInfo)
            public{

        require(payEth >= sInfo.registerEth, "not enough register fee");        

        DataSets.PlayerBaseInfo storage pBaseInfo = sInfo.playerBaseInfo[pid];
        bytes32 dealName = NameFilter.nameFilter(name);

        require(sInfo.playerAffNameIdx[dealName] == 0, "the name has registered");
        sInfo.playerAffNameIdx[dealName] = pid;
        pBaseInfo.name = dealName;

        payEth = payEth.sub(sInfo.registerEth);
        if ( payEth > 0){
            pBaseInfo.avaiEth = pBaseInfo.avaiEth.add(payEth);
        }

        // get aff id
        uint256 affID;
        if (affName != '' && affName != pBaseInfo.name){
            affID = sInfo.playerAffNameIdx[affName];
        }

        bool updateAffID = true;
        if (affID == 0 || affID == pid){
            affID = pBaseInfo.lastAffID;
            updateAffID = false;
        }

        // check cycle
        if(updateAffID){
            // DataSets.SystemRndParamRatio storage _pRatio = _rInfo.pRatio;
            uint256 _affID = affID;
            for(uint256 i = 0; i < 5; i++){
                if(_affID == 0){
                    break;
                }
                if(_affID == pid){
                    updateAffID = false;
                    break;
                }
                _affID = sInfo.playerBaseInfo[_affID].lastAffID;
            }

            if(updateAffID){
                pBaseInfo.lastAffID = affID;
            }
        }

        uint256 remainEth = sInfo.registerEth;
        if (affID != 0){
            uint256 nowAssignEth = sInfo.registerEth.mul(sInfo.registerAffRatio) / calcDecimal;
            DataSets.PlayerBaseInfo storage affBaseInfo = sInfo.playerBaseInfo[affID];

            playerAddAff(affBaseInfo, nowAssignEth);
            remainEth = remainEth.sub(nowAssignEth);
        }

        devAdd(sInfo, remainEth);
    }
}
