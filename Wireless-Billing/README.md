# Decentralized Wireless Billing Smart Contract

## Overview

This smart contract implements a comprehensive decentralized billing system for wireless telecommunications services on the Stacks blockchain. It provides subscription management, usage tracking, payment processing, and dispute resolution capabilities for wireless service providers and their customers.

## Features

### Core Functionality
- **Provider Registration**: Wireless service providers can register and create service plans
- **Subscription Management**: Users can subscribe to service plans with automatic renewal options
- **Usage Tracking**: Real-time tracking of data, voice, and SMS usage
- **Billing System**: Automated billing with base charges and overage calculations
- **Payment Processing**: STX-based payment system with user balance management
- **Dispute Resolution**: Built-in dispute filing and resolution mechanism
- **Reputation System**: Provider reputation scoring for transparency

### Key Benefits
- Transparent billing with immutable records
- Automated payment processing
- Decentralized dispute resolution
- Multi-provider ecosystem support
- Real-time usage monitoring
- Flexible subscription models

## Contract Architecture

### Data Structures

#### Service Plans
- Plan details including pricing, limits, and overage rates
- Provider-specific plan management
- Active/inactive status tracking

#### User Subscriptions
- Subscription details with start/end dates
- Auto-renewal configuration
- Service status management

#### Usage Records
- Real-time usage tracking per billing cycle
- Data, voice, and SMS consumption monitoring
- Cycle-based organization

#### Billing Records
- Transparent billing with base and overage charges
- Payment status tracking
- Due date management

#### Payment History
- Complete payment transaction records
- Multiple payment types support
- Transaction status tracking

#### Dispute Management
- Dispute filing with reason documentation
- Resolution tracking and refund processing
- Time-window enforcement

## Getting Started

### Prerequisites
- Stacks blockchain access
- STX tokens for transactions and payments
- Clarity smart contract development environment

### Deployment
1. Deploy the contract to the Stacks blockchain
2. The deployer becomes the contract owner with administrative privileges
3. Contract is active by default and ready for provider registration

## Usage Guide

### For Service Providers

#### 1. Register as Provider
```clarity
(register-provider "Provider Name" "Service description" "contact@provider.com")
```

#### 2. Create Service Plans
```clarity
(create-service-plan 
    "Unlimited Plan" 
    "Unlimited data and voice" 
    u1000000  ; 10 STX monthly
    u50000    ; 50GB data limit
    u2000     ; 2000 minutes
    u1000     ; 1000 SMS
    u100      ; Data overage rate
    u50       ; Voice overage rate
    u25)      ; SMS overage rate
```

#### 3. Record Customer Usage
```clarity
(record-usage customer-principal u1024 u60 u10) ; 1GB data, 60 min voice, 10 SMS
```

#### 4. Generate Bills
```clarity
(generate-bill customer-principal cycle-start-block)
```

### For Customers

#### 1. Deposit Funds
```clarity
(deposit-funds u5000000) ; Deposit 50 STX
```

#### 2. Subscribe to Plan
```clarity
(subscribe-to-plan provider-principal u1 true) ; Subscribe to plan 1 with auto-renewal
```

#### 3. Pay Bills
```clarity
(pay-bill provider-principal cycle-start-block)
```

#### 4. File Disputes
```clarity
(file-dispute provider-principal cycle-start u500000 "Incorrect overage charges")
```

#### 5. Cancel Subscription
```clarity
(cancel-subscription provider-principal)
```

## API Reference

### Provider Functions

#### register-provider
Registers a new wireless service provider.
- **Parameters**: name, description, contact-info
- **Returns**: Success boolean
- **Access**: Public

#### create-service-plan
Creates a new service plan with pricing and limits.
- **Parameters**: Plan details including pricing, limits, overage rates
- **Returns**: Plan ID
- **Access**: Registered providers only

#### update-service-plan
Updates existing service plan parameters.
- **Parameters**: plan-id and updated plan details
- **Returns**: Success boolean
- **Access**: Plan owner only

#### deactivate-plan
Deactivates a service plan.
- **Parameters**: plan-id
- **Returns**: Success boolean
- **Access**: Plan owner only

#### record-usage
Records customer usage for billing cycle.
- **Parameters**: user, data-mb, voice-minutes, sms-count
- **Returns**: Success boolean
- **Access**: Service provider only

#### generate-bill
Generates bill for customer billing cycle.
- **Parameters**: user, cycle-start
- **Returns**: Total bill amount
- **Access**: Service provider only

### Customer Functions

#### deposit-funds
Deposits STX tokens to user balance.
- **Parameters**: amount
- **Returns**: Success boolean
- **Access**: Public

#### subscribe-to-plan
Subscribes to a provider's service plan.
- **Parameters**: provider, plan-id, auto-renewal
- **Returns**: Success boolean
- **Access**: Public

#### cancel-subscription
Cancels active subscription.
- **Parameters**: provider
- **Returns**: Success boolean
- **Access**: Subscriber only

#### pay-bill
Pays outstanding bill from user balance.
- **Parameters**: provider, cycle-start
- **Returns**: Success boolean
- **Access**: Bill owner only

#### file-dispute
Files a dispute for billing issues.
- **Parameters**: provider, bill-cycle, disputed-amount, reason
- **Returns**: Dispute ID
- **Access**: Bill owner only

### Read-Only Functions

#### get-service-plan
Retrieves service plan details.
- **Parameters**: provider, plan-id
- **Returns**: Plan details or none

#### get-user-subscription
Gets user subscription information.
- **Parameters**: user, provider
- **Returns**: Subscription details or none

#### get-current-usage
Gets current billing cycle usage.
- **Parameters**: user, provider
- **Returns**: Usage details or none

#### get-billing-record
Retrieves billing record.
- **Parameters**: user, provider, cycle-start
- **Returns**: Billing details or none

#### get-user-balance
Gets user account balance.
- **Parameters**: user
- **Returns**: Balance details or none

#### get-provider-info
Gets provider information and reputation.
- **Parameters**: provider
- **Returns**: Provider details or none

#### is-service-active
Checks if service is active for user.
- **Parameters**: user, provider
- **Returns**: Boolean status

### Admin Functions

#### set-emergency-stop
Emergency contract shutdown mechanism.
- **Parameters**: stop (boolean)
- **Returns**: Success boolean
- **Access**: Contract owner only

#### resolve-dispute
Resolves customer disputes.
- **Parameters**: dispute-id, resolution, refund-amount
- **Returns**: Success boolean
- **Access**: Contract owner only

#### update-provider-reputation
Updates provider reputation score.
- **Parameters**: provider, new-score
- **Returns**: Success boolean
- **Access**: Contract owner only

## Constants and Limits

### Price Limits
- Minimum plan price: 0.001 STX (100 microSTX)
- Maximum plan price: 1,000 STX (1,000,000,000 microSTX)

### Time Windows
- Dispute window: 144 blocks (approximately 24 hours)
- Billing cycle: 4,320 blocks (approximately 30 days)
- Grace period: 144 blocks (approximately 24 hours)

### Usage Limits
- Maximum overage multiplier: 5x base rate
- Maximum data per usage record: 1TB
- Maximum voice minutes per record: 100,000 minutes
- Maximum SMS per record: 100,000 messages

## Error Codes

| Code | Error | Description |
|------|-------|-------------|
| 100 | err-owner-only | Function restricted to contract owner |
| 101 | err-not-found | Requested resource not found |
| 102 | err-unauthorized | Insufficient permissions |
| 103 | err-invalid-amount | Invalid monetary amount |
| 104 | err-insufficient-balance | Insufficient account balance |
| 105 | err-plan-not-active | Service plan is inactive |
| 106 | err-already-exists | Resource already exists |
| 107 | err-invalid-parameters | Invalid function parameters |
| 108 | err-payment-failed | Payment processing failed |
| 109 | err-dispute-window-closed | Dispute filing window expired |
| 110 | err-service-suspended | Service temporarily suspended |
| 111 | err-invalid-usage | Invalid usage data |
| 112 | err-refund-failed | Refund processing failed |
| 113 | err-invalid-input | Invalid input format |

## Security Features

### Access Control
- Provider-specific plan management
- User-specific subscription and payment controls
- Administrative functions restricted to contract owner

### Validation
- Comprehensive input validation for all parameters
- Principal address validation
- Amount and usage limit enforcement
- Time window validation for disputes

### Safety Mechanisms
- Emergency stop functionality
- Balance overflow protection
- Reasonable usage limits
- Payment verification before service activation

## Best Practices

### For Providers
1. Set reasonable overage rates (within 5x base price limit)
2. Regularly update service plan details
3. Monitor customer usage patterns
4. Respond promptly to disputes

### For Customers
1. Maintain sufficient balance for automatic payments
2. Monitor usage to avoid unexpected overages
3. Review bills promptly and file disputes within the window
4. Keep subscription details updated

### For Integration
1. Implement proper error handling for all contract calls
2. Validate user inputs before contract interaction
3. Monitor contract events for real-time updates
4. Implement backup payment mechanisms

## Technical Considerations

### Gas Optimization
- Efficient data structures minimize storage costs
- Batched operations where possible
- Optimized validation logic

### Scalability
- Cycle-based usage tracking for efficient storage
- Modular function design for easy updates
- Provider-specific data organization

### Interoperability
- Standard STX token integration
- Compatible with existing Stacks infrastructure
- Extensible design for future enhancements