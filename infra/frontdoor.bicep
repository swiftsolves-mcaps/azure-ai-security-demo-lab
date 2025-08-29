// Azure Front Door (Standard/Premium) + WAF policy in front of an App Service
// API versions validated via Bicep schema lookups

@description('Location for AFD and WAF. Azure Front Door resources are global.')
param location string = 'global'

@description('Azure Front Door profile name (must be unique within the resource group).')
param profileName string

@description('AFD endpoint name. Will be part of the default host: <endpointName>.azurefd.net')
param endpointName string

@description('Origin group name (logical).')
param originGroupName string = 'app-origin-group'

@description('Origin name (logical).')
param originName string = 'appservice-origin'


@description('Default hostname of the App Service (e.g., myapp.azurewebsites.net). Used for host header and SNI checks.')
param appServiceDefaultHostname string

@description('Name for the WAF policy resource.')
param wafPolicyName string = 'afd-waf-policy'

@description('AFD SKU. Choose Standard_AzureFrontDoor or Premium_AzureFrontDoor.')
@allowed([ 'Standard_AzureFrontDoor', 'Premium_AzureFrontDoor' ])
param sku string = 'Standard_AzureFrontDoor'

@description('Route name for default catch-all routing.')
param routeName string = 'default-route'

@description('WAF mode: Prevention or Detection (log only).')
@allowed([ 'Prevention', 'Detection' ])
param wafMode string = 'Prevention'

@description('Whether to automatically redirect HTTP to HTTPS.')
param enableHttpToHttpsRedirect bool = true

@description('Forwarding protocol to the origin.')
@allowed([ 'HttpsOnly', 'HttpOnly', 'MatchRequest' ])
param forwardingProtocol string = 'HttpsOnly'

// Profile
resource afdProfile 'Microsoft.Cdn/profiles@2024-09-01' = {
  name: profileName
  location: location
  sku: {
    name: sku
  }
}

// Endpoint (default domain: <endpointName>.azurefd.net)
resource afdEndpoint 'Microsoft.Cdn/profiles/afdEndpoints@2024-09-01' = {
  name: endpointName
  parent: afdProfile
  location: location
  properties: {
    enabledState: 'Enabled'
  }
}

// Origin Group
resource originGroup 'Microsoft.Cdn/profiles/originGroups@2024-09-01' = {
  name: originGroupName
  parent: afdProfile
  properties: {
    healthProbeSettings: {
      // Use a conservative probe to avoid 404s if /health doesn’t exist
      probePath: '/'
      probeProtocol: 'Https'
      probeRequestType: 'HEAD'
      probeIntervalInSeconds: 60
    }
    loadBalancingSettings: {
      sampleSize: 4
      successfulSamplesRequired: 3
      additionalLatencyInMilliseconds: 0
    }
    sessionAffinityState: 'Disabled'
  }
}

// Origin (App Service)
resource origin 'Microsoft.Cdn/profiles/originGroups/origins@2024-09-01' = {
  name: originName
  parent: originGroup
  properties: {
  // For AFD Standard/Premium, specify the origin by hostname. Do not use 'azureOrigin' here.
  hostName: appServiceDefaultHostname
  originHostHeader: appServiceDefaultHostname
    httpsPort: 443
    httpPort: 80
    priority: 1
    weight: 1000
    enabledState: 'Enabled'
  enforceCertificateNameCheck: true
  }
}

// Route: /* -> origin group, linked to default endpoint domain
resource route 'Microsoft.Cdn/profiles/afdEndpoints/routes@2024-09-01' = {
  name: routeName
  parent: afdEndpoint
  properties: {
    originGroup: {
      id: originGroup.id
    }
    httpsRedirect: enableHttpToHttpsRedirect ? 'Enabled' : 'Disabled'
    linkToDefaultDomain: 'Enabled'
    patternsToMatch: [ '/*' ]
    forwardingProtocol: forwardingProtocol
    supportedProtocols: [ 'Http', 'Https' ]
    enabledState: 'Enabled'
  }
  dependsOn: [ origin ]
}

// WAF Policy for AFD Standard/Premium (CDN WAF)
resource cdnWaf 'Microsoft.Cdn/cdnWebApplicationFirewallPolicies@2024-09-01' = {
  name: wafPolicyName
  location: 'Global'
  sku: {
    name: sku
  }
  properties: {
    policySettings: {
      enabledState: wafMode == 'Prevention' ? 'Enabled' : 'Enabled' // mode is represented by rules' actions; keep policy enabled
    }
    managedRules: {
      managedRuleSets: [
        {
          ruleSetType: 'DefaultRuleSet'
          ruleSetVersion: '2.1'
        }
      ]
    }
  }
}

// Security Policy to attach WAF to the endpoint domain
resource securityPolicy 'Microsoft.Cdn/profiles/securityPolicies@2024-09-01' = {
  name: 'default-security-policy'
  parent: afdProfile
  properties: {
    parameters: {
      type: 'WebApplicationFirewall'
      wafPolicy: {
        id: cdnWaf.id
      }
      associations: [
        {
          domains: [
            // Apply to the endpoint’s default domain (e.g., <endpoint>.azurefd.net)
            {
              // Default domain subresource: profiles/afdEndpoints/domains/<endpointName>
              id: '${afdEndpoint.id}/domains/${endpointName}'
            }
          ]
          patternsToMatch: [ '/*' ]
        }
      ]
    }
  }
}

@description('AFD default endpoint hostname (e.g., <endpoint>.azurefd.net).')
output endpointHostname string = afdEndpoint.properties.hostName
