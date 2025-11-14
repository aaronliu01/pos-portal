pragma solidity 0.6.6;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import {AccessControlMixin} from "../../../common/AccessControlMixin.sol";
import {ContextMixin} from "../../../common/ContextMixin.sol";
import {NativeMetaTransaction} from "../../../common/NativeMetaTransaction.sol";
import {IChildERC20Exit} from "./IChildERC20Exit.sol";
import {IChildToken} from "./IChildToken.sol";
import {IChildTokenForExchange} from "./IChildTokenForExchange.sol";

interface ISwapper {
    function swap(address fromToken, address toToken, uint256 amount) external;
}

interface IChildERC20Relay {
    function withdrawToByRelayer(
        address to,
        IChildToken tokenWithdraw,
        IChildToken tokenExit,
        uint256 amount,
        address relayer,
        bool withRefuel,
        uint256 expectedRefuelFee,
        uint256 expectedRelayerFee
    )
    external;
}

contract ChildERC20ExitWithSwap is
    AccessControlMixin,
    NativeMetaTransaction,
    ContextMixin,
    IChildERC20Exit
{
    event RelayExit(
        uint256 indexed id,
        address indexed relayer,
        address to,
        address tokenWithdraw,
        address tokenExit,
        uint256 actual,
        uint256 fee,
        bool withRefuel,
        uint256 refuelFee
    );

    using SafeERC20 for IERC20;

    uint256 public nonce;
    bool public isOpen = true;

    ISwapper public swapper;
    IChildERC20Relay public childERC20RelayProxy;

    constructor(
        address admin,
        address swapContract,
        address relayProxy
    ) public {
        _setupContractId("ChildERC20ExitWithSwap");
        _setupRole(DEFAULT_ADMIN_ROLE, admin);
        _initializeEIP712("ChildERC20ExitWithSwap");
        swapper = ISwapper(swapContract);
        childERC20RelayProxy = IChildERC20Relay(relayProxy);
    }

    modifier open() {
        require(isOpen, "The contract is not open");
        _;
    }

    function setOpen(bool flag) external only(DEFAULT_ADMIN_ROLE) {
        isOpen = flag;
    }

    function addMapping(
        IChildToken,
        IChildTokenForExchange,
        IChildTokenForExchange
    ) external override {
        revert("not support");
    }

    /**
     * @notice function to swap and withdraw ERC20 token automatically except btt interrelated token
     * @param to token receive address
     * @param tokenWithdraw token to withdraw
     * @param tokenExit token to exit
     * @param amount token amount
     */
    function withdrawTo(
        address to,
        IChildToken tokenWithdraw,
        IChildToken tokenExit,
        uint256 amount
    ) external override open {
        emit ExitTokenTo(
            msg.sender,
            to,
            address(tokenWithdraw),
            address(tokenExit),
            amount
        );

        IERC20(tokenWithdraw).safeTransferFrom(
            msgSender(),
            address(this),
            amount
        );

        if (tokenWithdraw == tokenExit) {
            tokenExit.withdrawTo(to, amount);
            return;
        }

        IERC20(tokenWithdraw).safeIncreaseAllowance(address(swapper), amount);
        swapper.swap(address(tokenWithdraw), address(tokenExit), amount);
        tokenExit.withdrawTo(to, amount);
    }

    function withdrawBTT(
        address,
        IChildToken,
        IChildToken,
        uint256
    ) external payable override {
        revert("not support");
    }

    function withdrawToByRelayerWrapper(
        address to,
        IChildToken tokenWithdraw,
        IChildToken tokenExit,
        uint256 amount,
        address relayer,
        bool withRefuel,
        uint256 expectedRefuelFee,
        uint256 expectedRelayerFee
    ) external open {
        uint256 _nonce = nonce + 1;
        nonce = _nonce;

        IERC20(tokenWithdraw).safeIncreaseAllowance(address(swapper), amount);
        swapper.swap(address(tokenWithdraw), address(tokenExit), amount);

        childERC20RelayProxy.withdrawToByRelayer(
            to,
            tokenExit,
            tokenExit,
            amount,
            payable(relayer),
            withRefuel,
            expectedRefuelFee,
            expectedRelayerFee
        );

        emit RelayExit(
            _nonce,
            relayer,
            to,
            address(tokenWithdraw),
            address(tokenExit),
            0,
            0,
            withRefuel,
            0
        );
    }
}
