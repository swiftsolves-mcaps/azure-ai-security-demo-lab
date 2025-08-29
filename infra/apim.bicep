@description('APIM service name (must start with a letter).')
param apimName string

@description('Location for APIM.')
param location string

@description('Publisher name (APIM required).')
param publisherName string = 'Publisher'

@description('Publisher email (APIM required).')
param publisherEmail string = 'noreply@example.com'

@description('App Service default hostname (e.g., myapp.azurewebsites.net).')
param appServiceHostname string

@description('Azure OpenAI endpoint (e.g., https://<account>.openai.azure.com). Leave empty to skip the genai API.')
param openAIEndpoint string = ''

@description('Application Insights connection string (for APIM logger). Leave empty to skip logger/diagnostics to App Insights.')
param appInsightsConnectionString string = ''

@description('Log Analytics Workspace Resource ID for Azure Monitor diagnostic settings. Leave empty to skip.')
param logAnalyticsWorkspaceId string = ''

@description('APIM SKU. Use StandardV2 for v2 platform (DeveloperV2 not available).')
@allowed([ 'BasicV2', 'StandardV2' ])
param skuName string = 'StandardV2'

@description('Units for APIM SKU (capacity).')
param skuCapacity int = 1

var serviceUrlApp = 'https://${appServiceHostname}'

resource apim 'Microsoft.ApiManagement/service@2024-05-01' = {
  name: apimName
  location: location
  sku: {
    name: skuName
    capacity: skuCapacity
  }
  properties: {
    publisherEmail: publisherEmail
    publisherName: publisherName
  }
}

// Logger to Application Insights (optional)
resource aiLogger 'Microsoft.ApiManagement/service/loggers@2024-05-01' = if (appInsightsConnectionString != '') {
  name: 'ai-logger'
  parent: apim
  properties: {
    loggerType: 'applicationInsights'
    credentials: {
      // Connection string supported by APIM; instrumentationKey also works if extracted
      connectionString: appInsightsConnectionString
    }
    description: 'Logger to Application Insights'
    isBuffered: true
  }
}

// APIM Diagnostics to App Insights (optional)
resource apimDiag 'Microsoft.ApiManagement/service/diagnostics@2024-05-01' = if (appInsightsConnectionString != '') {
  name: 'apim-ai'
  parent: apim
  properties: {
    loggerId: aiLogger.id
    sampling: {
      percentage: 10
      samplingType: 'fixed'
    }
    frontend: {
      request: {
        headers: [ 'User-Agent', 'Authorization' ]
        body: {
          bytes: 0
        }
      }
      response: {
        headers: [ '*' ]
        body: {
          bytes: 0
        }
      }
    }
    backend: {
      request: {
        headers: [ '*' ]
        body: {
          bytes: 0
        }
      }
      response: {
        headers: [ '*' ]
        body: {
          bytes: 0
        }
      }
    }
  }
}

// Azure Monitor Diagnostic Settings to Log Analytics (optional)
resource diagSettings 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = if (logAnalyticsWorkspaceId != '') {
  name: 'apim-to-law'
  scope: apim
  properties: {
    workspaceId: logAnalyticsWorkspaceId
    logs: [
      for c in [
        'GatewayLogs', 'WebSocketLogs', 'RequestResponseBodies', 'TenantLogs', 'AllMetrics'
      ]: {
        category: c
        enabled: true
        retentionPolicy: {
          days: 0
          enabled: false
        }
      }
    ]
    metrics: [
      {
        category: 'AllMetrics'
        enabled: true
        retentionPolicy: {
          days: 0
          enabled: false
        }
      }
    ]
  }
}

// Backend: App Service
resource backendApp 'Microsoft.ApiManagement/service/backends@2024-05-01' = {
  name: 'app-backend'
  parent: apim
  properties: {
    url: serviceUrlApp
    protocol: 'http'
    // HTTPS to backend; APIM sets TLS automatically for https URLs
  }
}

// API: backend App Service API exposed under base path 'rag-api'
resource apiRag 'Microsoft.ApiManagement/service/apis@2024-05-01' = {
  name: 'rag-api'
  parent: apim
  properties: {
    displayName: 'RAG API'
    path: 'rag-api'
    protocols: [ 'https' ]
    serviceUrl: serviceUrlApp
  }
}

// Policy to rewrite /rag-api/* to backend /api/*
resource apiRagPolicy 'Microsoft.ApiManagement/service/apis/policies@2024-05-01' = {
  name: 'policy'
  parent: apiRag
  properties: {
    format: 'rawxml'
    value: '<policies>\n  <inbound>\n    <base />\n    <rewrite-uri template="/api{@(context.Request.OriginalUrl.Path.Substring(context.Api.Path.Length))}" />\n    <set-backend-service backend-id="app-backend" />\n  </inbound>\n  <backend>\n    <base />\n  </backend>\n  <outbound>\n    <base />\n  </outbound>\n  <on-error>\n    <base />\n  </on-error>\n</policies>'
  }
}

// Wildcard operations for rag-api to allow any path/method
resource apiRagOpGet 'Microsoft.ApiManagement/service/apis/operations@2024-05-01' = {
  name: 'wildcard-get'
  parent: apiRag
  properties: {
    displayName: 'Wildcard GET'
    method: 'GET'
    urlTemplate: '/{*path}'
  }
}

resource apiRagOpPost 'Microsoft.ApiManagement/service/apis/operations@2024-05-01' = {
  name: 'wildcard-post'
  parent: apiRag
  properties: {
    displayName: 'Wildcard POST'
    method: 'POST'
    urlTemplate: '/{*path}'
  }
}

// Optional: OpenAI proxy API at /genai if endpoint provided
resource backendOpenAI 'Microsoft.ApiManagement/service/backends@2024-05-01' = if (openAIEndpoint != '') {
  name: 'openai-backend'
  parent: apim
  properties: {
    url: openAIEndpoint
    protocol: 'http'
  }
}

resource apiGenAI 'Microsoft.ApiManagement/service/apis@2024-05-01' = if (openAIEndpoint != '') {
  name: 'genai'
  parent: apim
  properties: {
    displayName: 'Azure OpenAI Proxy'
    path: 'genai'
    protocols: [ 'https' ]
    serviceUrl: openAIEndpoint
  }
}

resource apiGenAIPolicy 'Microsoft.ApiManagement/service/apis/policies@2024-05-01' = if (openAIEndpoint != '') {
  name: 'policy'
  parent: apiGenAI
  properties: {
    format: 'rawxml'
  value: '<policies>\n  <inbound>\n    <base />\n    <rewrite-uri template="/@(context.Request.OriginalUrl.Path.Substring(context.Api.Path.Length))" />\n    <set-backend-service backend-id="openai-backend" />\n  </inbound>\n  <backend>\n    <base />\n  </backend>\n  <outbound>\n    <base />\n  </outbound>\n  <on-error>\n    <base />\n  </on-error>\n</policies>'
  }
}

// Wildcard operations for genai
resource apiGenAIOpGet 'Microsoft.ApiManagement/service/apis/operations@2024-05-01' = if (openAIEndpoint != '') {
  name: 'wildcard-get'
  parent: apiGenAI
  properties: {
    displayName: 'Wildcard GET'
    method: 'GET'
    urlTemplate: '/{*path}'
  }
}

resource apiGenAIOpPost 'Microsoft.ApiManagement/service/apis/operations@2024-05-01' = if (openAIEndpoint != '') {
  name: 'wildcard-post'
  parent: apiGenAI
  properties: {
    displayName: 'Wildcard POST'
    method: 'POST'
    urlTemplate: '/{*path}'
  }
}

@description('APIM gateway host (e.g., <apimName>.azure-api.net).')
output apimHostname string = '${apimName}.azure-api.net'
