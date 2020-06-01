pragma solidity ^0.4.25;

library DataSets{
    //////////////////////////////////////// define base struct
    
    struct LastPersonBuyInfo{
        uint256 pid;
        uint256 tickets;
    }

    struct PersonOpenTicketInfo{
        uint256 pid;
        uint256 tickets;
    }

    struct PersonAwardRecord{
        uint256 ticketPos;
        uint256 awardLevel;
    }

    struct SystemRndFlag{
        bool alreadInitParam; // this round has default init
        bool ended; // can't buy ticket
        bool terminate;
        bool urAwardEnd;
    }
        
    struct SystemRndTime{
        uint256 startTime;
        uint256 endTime;
    }

    struct SystemRndTicket{
        uint256 eth; // total eth        
        uint256 tickets; // now total tickets, no decimal num
        uint256 mask;

        uint256 newBuyID; // for log event;

        // cycle queue, record last person of buy action.
        uint256 lastQueueFirst;
        LastPersonBuyInfo[] lastPersonQueue;

        uint256 totalSharedEth;
        uint256 totalAffEth;
        uint256 totalTickets;
    }

    struct SystemRndOpenTicket{
        uint256 k;
        uint256 fk; // k factor, for fix price

        // 0: user open ticket
        // 1: lock, and compute award num
        // 2: publish award
        uint256 step;

        uint256 nowOpenTicketCounterID; // start for 1
        uint256 penddingTickets;
        bytes32 nowOpenHash;

        PersonOpenTicketInfo[] waitForOpen;
        uint256 newWaitForOpenID; // start for 1

        uint256[3] nowAwardNum; // 0: R, 1: SR, 2: SSR
        uint256[3] award;
        uint256 nowURAwardNum;
        // debug:
        uint256[3] _probability;
        uint256[3] _exp;

        // total for statistic
        uint256 totalWinEth;
        uint256[3] totalAwardNum; // 0: R, 1: SR, 2: SSR

        mapping(uint256 => uint256) maskSnap;
    }

    struct SystemRndPool{
        uint256 discountPool;
        uint256 awardPool;
        uint256 nextDiscountPool;
    }

    struct SystemRndParamPrice{
        // price
        uint256 a;
        uint256 aSqrt;
        uint256 b;
    }

    struct SystemRndParamProtect{
        // start protect
        uint256 duration;
        bytes32 secret; // must set by manual
    }
    
    struct SystemRndParamICO{
        // ICO
        uint256 totalEth;
        uint256 perAddrEth;
    }

    struct SystemRndParamAssign{
        // buy ticket eth assign
        uint256 tAff;
        uint256 tShare;
        uint256 tAward;

        // award pool assign
        uint256 aBigWin;
        uint256 aOtherWin;
        uint256 aDiscount; // to next discount pool
        uint256 lastPersonNum; // how many person to share other win;
    }
    
    struct SystemRndParamOpenTicket{
        uint256[3] exp; // 0: R, 1: SR, 2: SSR
        uint256[3] factor; // 0: R, 1: SR, 2: SSR
        
        uint256 urRatio;

        uint256 ticketOpenMin;
    }

    struct SystemRndParamTime{
        // count down
        uint256 timeMax;
        uint256 timeInit;
        uint256 timeAdd;
        uint256 startTimeInterval;
    }

    struct SystemRndParamRatio{
        // auto buy
        uint256 autoBuyFee;

        // discount level
        uint256[6] discountLevel;

        // aff ratio
        uint256[5] affRatio;
    }
    
    //////////////////////////////////////// define system struct
    
    struct SystemInfo{
        uint256 finishSetSecretHash;
        bytes32[10] openSecretHashs;
        uint256 nowOpenHashID;

        uint256 registerAffRatio;
        uint256 registerEth;

        uint256 rndIdx; // first round idx = 1;

        uint256 devID;

        // player
        // pid->rid->data
        mapping (uint256 => mapping(uint256 => PlayerRndInfo)) playerRndInfo;
        // pid->data
        mapping (uint256 => PlayerBaseInfo) playerBaseInfo;

        // player mapping
        // address->pid
        mapping (address => uint256) playerAddrIdx;
        // affName->pid
        mapping (bytes32 => uint256) playerAffNameIdx;
    }

    struct RoundInfo{
        // info
        SystemRndFlag rFlag;
        SystemRndTime rTime;
        SystemRndTicket rTicket;
        SystemRndOpenTicket rOpenTicket;
        SystemRndPool rPool;

        // param
        SystemRndParamPrice pPrice;
        SystemRndParamProtect pProtect;
        SystemRndParamICO pICO;
        SystemRndParamAssign pAssign;
        SystemRndParamOpenTicket pOpenTicket;
        SystemRndParamTime pTime;
        SystemRndParamRatio pRatio;
    }

    //////////////////////////////////////// define player struct
    
    struct PlayerRndInfo{
        bool enableAutoBuy;

        bool ensureLevel;
        uint8 level; // vip level

        uint256 lastPersonCounter; // 0=not last person; >0 counter for person num;
        
        uint256 autoBuyTicketNum;
        
        uint256 eth;
        uint256 payEth;
        
        uint256 nowTickets; // 
        uint256 totalTickets;
        uint256 mask;

        uint256 penddingTickets; // 
        uint256 waitForOpenID;
        uint256 lastOpenTicketCounterID;
    }

    struct PlayerBaseInfo{
        bytes32 name;
        address addr;
        uint256 ID; // self id

        uint256 lastAffID; // last used aff id
        uint256 lastRoundID;
        
        uint256 winEth; // win eth
        uint256 affEth;
        uint256 sharedEth;
        uint256 avaiEth; // assign eth
    }
}
