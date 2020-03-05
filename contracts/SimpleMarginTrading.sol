pragma solidity ^0.5.9;
pragma experimental ABIEncoderV2;

// libraries
import "@0x/contracts-exchange-libs/contracts/src/LibFillResults.sol";
import "@0x/contracts-erc20/contracts/src/LibERC20Token.sol";
import "@0x/contracts-utils/contracts/src/LibSafeMath.sol";

// interfaces
import "@0x/contracts-erc20/contracts/src/interfaces/IERC20Token.sol";
import "@0x/contracts-exchange/contracts/src/interfaces/IExchange.sol";
import "@0x/contracts-asset-proxy/contracts/src/interfaces/IAssetData.sol";
import "@0x/contracts-erc20/contracts/src/interfaces/IEtherToken.sol";
import "./interfaces/ICERC20.sol";
import "./interfaces/ICEther.sol";
import "./interfaces/IComptroller.sol";

contract SimpleMarginTrading
{
    using LibSafeMath for uint256;

    // constants
    uint256 constant internal MAX_UINT = uint256(-1);

    // contract references
    address payable internal owner;
    IExchange internal exchange;
    IComptroller internal comptroller;
    ICERC20 internal cdai;
    ICEther internal ceth;
    IEtherToken internal weth;
    IERC20Token internal dai;

    // margin position related variables
    uint256 internal positionBalance = 0; // total position size (ETH locked in ceth + weth + contract balance)

    // structs
    struct ZeroExQuote {
        address buyToken;
        address sellToken;
        uint256 buyAmount;
        uint256 sellAmount;
        uint256 protocolFee;
        bytes calldataHex;
    }

    constructor (
        address _exchange,
        address _comptroller,
        address _cdai,
        address _dai,
        address payable _ceth,
        address _weth
        )
        public
    {
        exchange = IExchange(_exchange);
        comptroller = IComptroller(_comptroller);
        cdai = ICERC20(_cdai);
        ceth = ICEther(_ceth);
        weth = IEtherToken(_weth);
        dai = IERC20Token(_dai);

        owner = msg.sender;

        // Enter markets
        _enterMarkets();
    }

    // receive ETH
    function () external payable {
    }

    // modifiers
    modifier onlyowner() {
        require(msg.sender == owner, "permission denied");
        _;
    }

    modifier onlyWhenClosed() {
        require(positionBalance == 0, "position not closed");
        _;
    }

    modifier onlyWhenOpen() {
        require(positionBalance != 0, "position not open");
        _;
    }

    function _enterMarkets()
        internal
    {
        address[] memory markets = new address[](2);
        markets[0] = address(ceth);
        markets[1] = address(cdai);
        uint[] memory errors = comptroller.enterMarkets(markets);
        require(errors[0] == 0, "ceth cant enter market");
        require(errors[1] == 0, "Cdai cant enter market");
    }

    function _getZeroExApprovalAddress()
        internal
        view
        returns (address)
    {
        bytes4 erc20ProxyId = IAssetData(address(0)).ERC20Token.selector;
        return exchange.getAssetProxy(erc20ProxyId);
    }

    function _approve(address token, address delegated)
        internal
    {
        LibERC20Token.approve(token, delegated, MAX_UINT);
    }

    function open(ZeroExQuote memory quote)
        public
        payable
        onlyowner
        onlyWhenClosed
        returns (uint256 positionBalance, uint256 borrowBalance)
    {
        // 1. increase position by msg.value - protocolFee
        positionBalance = msg.value.safeSub(quote.protocolFee);
        // 2. mint collateral in compound
        ceth.mint.value(positionBalance)();
        // 3. borrow token
        require(cdai.borrow(quote.sellAmount) == 0, "Failed to borrow cDAI from Compound Finance");
        // 4. approve 0x exchange to move DAI
        _approve(address(dai), _getZeroExApprovalAddress());
        // 5. verify quote is valid
        require(quote.sellToken == address(weth), "Provided quote is not selling WEth");
        require(quote.buyToken == address(dai), "Provided quote is not buying Dai");
        // 6. execute swap
        (bool success, bytes memory data) = address(exchange).call.value(quote.protocolFee)(quote.calldataHex);
        require(success, "Swap not filled");
        // 7. decode fill results
        LibFillResults.FillResults memory fillResults = abi.decode(data, (LibFillResults.FillResults));
        // 8. position size increase by bought amount of WETH
        positionBalance.safeAdd(fillResults.makerAssetFilledAmount);
        borrowBalance = cdai.borrowBalanceCurrent(address(this));
        // at this point you have ceth, and swapped for WETH
    }

    function close(
       ZeroExQuote memory quote
    )
        public
        onlyowner
        onlyWhenOpen
        returns (uint ethBalance)
    {
        // 1. approve for swap
        _approve(address(weth), _getZeroExApprovalAddress());
        // 2. verify swap
        uint256 wethBalance = weth.balanceOf(address(this));
        uint256 daiBorrowBalance = cdai.borrowBalanceCurrent(address(this));
        require(wethBalance >= quote.sellAmount, "Provided quote doesn't provide sufficient liquidity");
        require(quote.buyToken == address(dai), "Provided quote doesn't buy DAI");
        require(daiBorrowBalance < quote.buyAmount, "Provided quote doesn't provide sufficient liquidity");
        // 3. execute swap
        (bool success, bytes memory data) = address(exchange).call.value(quote.protocolFee)(quote.calldataHex);
        require(success, "Swap not filled");
        // 4. decode results
        LibFillResults.FillResults memory fillResults = abi.decode(data, (LibFillResults.FillResults));
        // 5. return back dai
        _approve(address(dai), address(cdai));
        require(cdai.repayBorrow(fillResults.makerAssetFilledAmount) == 0, "Repayment of DAI to Compound Finance failed");
        // 6. get back ETH
        require(ceth.redeem(ceth.balanceOfUnderlying(address(this))) == 0, "Withdrawal of ETH from Compound Financefailed");
        // 7. withdraw all weth Balance;
        weth.withdraw(wethBalance);
        // 8. transfer all ETH back to owner;
        ethBalance = address(this).balance;
        owner.transfer(address(this).balance);
        // 9. reset balance
        positionBalance = 0;
    }

    // handy function to get borrowed dai amount
    function getBorrowBalance()
        public
        onlyowner
        returns (uint256)
    {
        return cdai.borrowBalanceCurrent(address(this));
    }
}
