// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract CorporateRetailStore {
    enum ShippingOption { Standard, Express, Overnight }
    enum DiscountType { Flat, Percentage }

    struct Product {
        string name;
        uint256 price;
        uint256 quantity;
        address vendor;
    }

    struct Order {
        address buyer;
        uint256 totalAmount;
        bool fulfilled;
        ShippingOption shipping;
    }

    struct Discount {
        DiscountType dtype;
        uint256 value;
        uint256 validUntil;
    }

    struct MultiSigApproval {
        uint256 approvals;
        mapping(address => bool) approvedBy;
    }

    mapping(uint256 => Product) public products;
    mapping(uint256 => Order) public orders;
    mapping(uint256 => Discount) public discounts;
    mapping(uint256 => MultiSigApproval) public highValueApprovals;

    address public owner;
    address[] public approvers;

    uint256 public nextProductId = 1;
    uint256 public nextOrderId = 1;
    uint256 public nextDiscountId = 1;

    uint256 public highValueThreshold = 100 ether;

    event NewOrder(uint256 orderId, address indexed buyer, uint256 totalAmount, ShippingOption shipping);
    event NewProduct(uint256 productId, string name, uint256 price, uint256 quantity, address vendor);
    event OrderFulfilled(uint256 orderId, address indexed buyer);
    event NewDiscount(uint256 discountId, DiscountType dtype, uint256 value, uint256 validUntil);
    event HighValueOrderApproved(uint256 orderId, address approver);

    modifier onlyOwner() {
        require(msg.sender == owner, "Only the owner can perform this action");
        _;
    }

    modifier onlyVendor(uint256 productId) {
        require(msg.sender == products[productId].vendor, "Only the vendor can perform this action");
        _;
    }

    modifier onlyApprover() {
        bool isApprover = false;
        for (uint i = 0; i < approvers.length; i++) {
            if (approvers[i] == msg.sender) {
                isApprover = true;
                break;
            }
        }
        require(isApprover, "Only an approver can perform this action");
        _;
    }

    constructor(address[] memory _approvers) {
        owner = msg.sender;
        approvers = _approvers;
    }

    function addProduct(string memory name, uint256 price, uint256 quantity) public returns (uint256) {
        products[nextProductId] = Product(name, price, quantity, msg.sender);
        emit NewProduct(nextProductId, name, price, quantity, msg.sender);
        return nextProductId++;
    }

    function updateProduct(uint256 productId, string memory name, uint256 price, uint256 quantity) public onlyVendor(productId) {
        products[productId] = Product(name, price, quantity, msg.sender);
    }

    function addDiscount(uint256 productId, DiscountType dtype, uint256 value, uint256 validUntil) public onlyVendor(productId) {
        discounts[nextDiscountId] = Discount(dtype, value, validUntil);
        emit NewDiscount(nextDiscountId, dtype, value, validUntil);
        nextDiscountId++;
    }

    function placeOrder(
        uint256[] memory productIds,
        uint256[] memory quantities,
        ShippingOption shippingOption,
        string memory shippingAddress
    ) public payable returns (uint256) {
        require(productIds.length == quantities.length, "Mismatch between product IDs and quantities");

        uint256 totalAmount = 0;

        for (uint i = 0; i < productIds.length; i++) {
            uint256 productId = productIds[i];
            uint256 quantity = quantities[i];

            Product storage product = products[productId];
            require(product.quantity >= quantity, "Insufficient product quantity");

            uint256 discountedPrice = applyDiscount(productId, product.price);
            totalAmount += discountedPrice * quantity;
        }

        uint256 shippingCost = getShippingCost(shippingOption);
        require(msg.value >= totalAmount + shippingCost, "Insufficient funds sent");

        orders[nextOrderId] = Order(msg.sender, totalAmount, false, shippingOption);
        emit NewOrder(nextOrderId, msg.sender, totalAmount, shippingOption);

        if (totalAmount >= highValueThreshold) {
            highValueApprovals[nextOrderId].approvals = 0;
        }

        uint256 refundAmount = msg.value - totalAmount - shippingCost;
        if (refundAmount > 0) {
            payable(msg.sender).transfer(refundAmount);
        }

        return nextOrderId++;
    }

    function approveHighValueOrder(uint256 orderId) public onlyApprover {
        require(orders[orderId].totalAmount >= highValueThreshold, "Not a high-value order");
        require(!highValueApprovals[orderId].approvedBy[msg.sender], "Already approved by this approver");

        highValueApprovals[orderId].approvals++;
        highValueApprovals[orderId].approvedBy[msg.sender] = true;
        emit HighValueOrderApproved(orderId, msg.sender);

        if (highValueApprovals[orderId].approvals >= approvers.length / 2) {
            fulfillOrder(orderId);
        }
    }

    function fulfillOrder(uint256 orderId) public {
        Order storage order = orders[orderId];
        require(!order.fulfilled, "Order already fulfilled");

        order.fulfilled = true;
        emit OrderFulfilled(orderId, order.buyer);
    }

    function getShippingCost(ShippingOption option) public pure returns (uint256) {
        if (option == ShippingOption.Standard) {
            return 0.01 ether;
        } else if (option == ShippingOption.Express) {
            return 0.02 ether;
        } else if (option == ShippingOption.Overnight) {
            return 0.05 ether;
        }
        return 0;
    }

    function applyDiscount(uint256 productId, uint256 originalPrice) internal view returns (uint256) {
        Discount storage discount = discounts[productId];
        if (discount.validUntil >= block.timestamp) {
            if (discount.dtype == DiscountType.Flat) {
                return originalPrice - discount.value;
            } else if (discount.dtype == DiscountType.Percentage) {
                return originalPrice * (100 - discount.value) / 100;
            }
        }
        return originalPrice;
    }
}
