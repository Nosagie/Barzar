pragma solidity ^0.5.0;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts/ownership/Secondary.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";



contract Market is Secondary{
    using SafeMath for uint256;

    mapping(address => uint256) private collateralDeposits;
    mapping(address => uint256) private bidDeposits;
    mapping(address => bool) private bidders;

    address payable[] private biddersAddresses;

    address payable private seller;
    address payable private winningBidder;
    uint256 private confirmationStartTime;
    uint256 private confirmationEndTime;
    uint256 private deliveryDays;
    bool private buyerReceivedGoods;

    bytes32 private marketID;
    string private productName;
    string private description;
    string private imageURL;
    uint256 public bidPeriodStartTime;
    uint256 public bidPeriodEndTime;

    modifier activeBidPeriod {
        require(bidPeriodEndTime > now,"Bid period Over");
        _;
    }

    constructor(address payable _seller,string memory _productName,string memory _description,
        string memory _imageUrl,uint256 _daysToExpiry) public payable onlyPrimary
    {
        require(_daysToExpiry <= 10,"Markets cannot be valid for more than 10 days");

        seller = _seller;
        collateralDeposits[_seller] = msg.value;
        productName = _productName;
        description = _description;
        imageURL = _imageUrl;
        buyerReceivedGoods = false;
        bidPeriodStartTime = block.timestamp;
        // bidPeriodEndTime = block.timestamp + (_daysToExpiry * 1 days);
        bidPeriodEndTime = block.timestamp + (_daysToExpiry * 1 minutes);
        marketID = keccak256(abi.encodePacked(bidPeriodStartTime,msg.value,productName,bidPeriodEndTime,description));
    }

    function getMarketDetails() public view returns
    (bytes32,string memory,string memory,string memory,uint256,uint256)
    {
        return (marketID,productName,description,imageURL,bidPeriodStartTime,
                bidPeriodEndTime);
    }

    function getConfirmationStartTime() public view
    returns (uint256)
    {
        require((msg.sender == seller)||(msg.sender == winningBidder),
                "You are not a market Participant");
        return confirmationStartTime;
    }

    function getConfirmationEndTime() public view
    returns (uint256)
    {
        require((msg.sender == seller)||(msg.sender == winningBidder),
                "You are not a market Participant");
        return confirmationEndTime;
    }


    // create new bid
    function createBid(uint256 _bidAmount,uint256 _collateralAmount) public
        payable activeBidPeriod
        {
            require(msg.sender != seller,"Seller cannot bid in their market");
            require(msg.value >= _bidAmount.add(_collateralAmount),"Not enough money sent");
            collateralDeposits[msg.sender] = _collateralAmount;
            bidDeposits[msg.sender] = _bidAmount;
            biddersAddresses.push(msg.sender);
            bidders[msg.sender] = true;

        }

    function isBidder(address toCheck) public view returns (bool){
        return bidders[toCheck];
    }

    function getSeller() public view returns (address)
    {
        return seller;
    }

    function getMarketId() public view returns (bytes32){
        return marketID;
    }

    // withdraw active bid insofar as it is not the winning bid
    // gives seller incentive to pick winner, else all bids go away
    function withdrawBid() public activeBidPeriod
    {
        address payable _bidder = msg.sender;
        require(bidders[_bidder] == true,"Not a valid bidder in market");
        require(_bidder != winningBidder,"You won the auction");
        require(now > bidPeriodEndTime,"Cannot cancel after bid period over");

        bidders[_bidder] = false;
        uint256 toSend = collateralDeposits[_bidder].add(bidDeposits[_bidder]);
        collateralDeposits[_bidder] = 0;
        bidDeposits[_bidder] = 0;

        _bidder.transfer(toSend);
    }

    // buyer confirm receipt of good
    function buyerConfirmReceipt() public
    {
        address payable _buyerAddress = msg.sender;
        require(_buyerAddress == winningBidder,"You did not win auction");
        require(confirmationEndTime < now,"Confirmation Period Over");
        uint256 bidderCollateral = collateralDeposits[_buyerAddress];
        buyerReceivedGoods = true;
        collateralDeposits[_buyerAddress] = 0;
        _buyerAddress.transfer(bidderCollateral);
    }

    //seller selects winning bid
    function selectWinningBid(address payable _bidderAddress,uint256 _deliveryDays)
        public
    {
        address payable _seller = msg.sender;
        require(deliveryDays <= 14,"Delivery days must be less than or equal to 14");
        require(bidders[_bidderAddress],"Not a valid bidder");
        require(_seller == seller,"Not your market");
        require(winninBidder == address(0),"You have already selected a winner");
        // require(bidPeriodEndTime < now,"Bidding period not over");

        bidPeriodEndTime = now;//end bidding period
        winningBidder = _bidderAddress;
        deliveryDays = _deliveryDays;
        confirmationStartTime = now;
        confirmationEndTime = now + (_deliveryDays * 1 days);

        //check/return everyone else's collateral and bid
        for (uint i = 0; i < biddersAddresses.length;i++){
            address payable bidderAdd = biddersAddresses[i];
            if (bidders[bidderAdd] && winningBidder != bidderAdd){
                uint256 _collateral = collateralDeposits[bidderAdd];
                uint256 _bid = bidDeposits[bidderAdd];
                bidDeposits[bidderAdd] = 0;
                collateralDeposits[bidderAdd] = 0;
                bidders[bidderAdd] = false;

                bidderAdd.transfer(_collateral.add(_bid));
            }
        }
    }

    // get seller collateral after transaction
    function getSellerPaymentAndCollateral() public
    {
        address payable _seller = msg.sender;
        require(seller == _seller,"You are not the seller");

        if (buyerReceivedGoods && (now > confirmationEndTime)){
            // return collateral to seller
            uint256 collateral = collateralDeposits[seller];
            uint256 bidAmount = bidDeposits[winningBidder];
            collateralDeposits[seller] = 0;
            bidDeposits[seller] = 0;

            seller.transfer(collateral.add(bidAmount));
        }
        else if((buyerReceivedGoods==false) && (now > confirmationEndTime)){ //both lose deposits
            uint256 collateralS = collateralDeposits[seller];
            uint256 collateralB = collateralDeposits[winningBidder];
            uint256 bidAmount = bidDeposits[winningBidder];
            collateralDeposits[seller] = 0;
            collateralDeposits[winningBidder] = 0;
            bidDeposits[winningBidder] = 0;

            // recipient of deposits
            address payable beneficiary = address(uint160(primary()));

            // return bidamount and keep deposits
            beneficiary.transfer(collateralB.add(collateralS));
            winningBidder.transfer(bidAmount);
        }
        else
            revert("You can only get collateral after confirmation period");
        }

   function sellerCancelMarket() public
    {
        address payable _seller = msg.sender;
        require(_seller == seller,"You are not the seller");
        require(winningBidder == address(0), "You cannot cancel the market after sellecting a winning bid");

        for(uint i = 0; i < biddersAddresses.length;i++)
        {
            address payable bidderAdd = biddersAddresses[i];
            if (bidders[bidderAdd]){
                uint256 _collateral = collateralDeposits[bidderAdd];
                uint256 _bid = bidDeposits[bidderAdd];
                bidDeposits[bidderAdd] = 0;
                collateralDeposits[bidderAdd] = 0;
                bidders[bidderAdd] = false;

                bidderAdd.transfer(_collateral.add(_bid));
            }
        }
        // return seller collateral
        uint256 sellerCollateral = collateralDeposits[seller];
        collateralDeposits[seller] = 0;
        seller.transfer(sellerCollateral);
    }


    // for each day seller loses percentage of collateral to buyer and platform
    function sellerExtendDelivery(uint256 _extensionDays) public
    {
        address payable _requester = msg.sender;
        require(_requester == seller,"You are not the seller in this market");
        require(_extensionDays <= 15,"Maximum two week extension");

        uint256 sCollateral = collateralDeposits[seller];
        uint256 toLose = sCollateral.mul(1).mul(_extensionDays);
        collateralDeposits[seller] = sCollateral.sub(toLose);

        // recipient of deposits
        address payable beneficiary = address(uint160(primary()));

        winningBidder.transfer(toLose.div(2));
        beneficiary.transfer(toLose.div(2));

        confirmationEndTime = confirmationEndTime + (_extensionDays * 1 days);
    }

}