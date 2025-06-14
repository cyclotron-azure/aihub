data "azurerm_subscription" "current" {}

data "azurerm_client_config" "current" {}

data "http" "current_ip" {
  url   = "http://ipv4.icanhazip.com"
  count = var.use_private_endpoints ? 1 : 0
}

resource "random_id" "random" {
  byte_length = 8
}

locals {
  allowed_ips             = var.use_private_endpoints ? concat(var.allowed_ips, ["${chomp(data.http.current_ip[0].response_body)}"]) : var.allowed_ips
  sufix                   = var.use_random_suffix ? substr(lower(random_id.random.hex), 1, 5) : ""
  name_sufix              = var.use_random_suffix ? "-${local.sufix}" : ""
  resource_group_name     = "${var.resource_group_name}${local.name_sufix}"
  storage_account_name    = "${var.storage_account_name}${local.sufix}"
  azopenai_name           = "${var.azopenai_name}${local.name_sufix}"
  content_safety_name     = "${var.content_safety_name}${local.name_sufix}"
  cognitive_services_name = "${var.cognitive_services_name}${local.name_sufix}"
  speech_name             = "${var.speech_name}${local.name_sufix}"
  vision_name             = "${var.vision_name}${local.name_sufix}"
  bing_name               = "${var.bing_name}${local.name_sufix}"
  search_name             = "${var.search_name}${local.name_sufix}"
  form_recognizer_name    = "${var.form_recognizer_name}${local.name_sufix}"
  apim_name               = "${var.apim_name}${local.name_sufix}"
  appi_name               = "${var.appi_name}${local.name_sufix}"
  log_name                = "${var.log_name}${local.name_sufix}"
  cae_name                = "${var.cae_name}${local.name_sufix}"
  ca_chat_name            = "${var.ca_chat_name}${local.name_sufix}"
  ca_prep_docs_name       = "${var.ca_prep_docs_name}${local.name_sufix}"
  ca_aihub_name           = "${var.ca_aihub_name}${local.name_sufix}"

  ai_services_name        = "${var.ai_services_name}${local.name_sufix}"
  ai_foundry_name         = "${var.ai_foundry_name}${local.name_sufix}"
  ai_foundry_project_name = "${var.ai_foundry_project_name}${local.name_sufix}"
  ai_foundry_kv_name      = "${var.ai_foundry_kv_name}${local.name_sufix}"
  ai_foundry_st_name      = "${var.ai_foundry_st_name}${local.sufix}"
  bing_account_name       = "${var.bing_account_name}${local.name_sufix}"

  func_name = "plugin${local.sufix}"
  cv_name   = "${var.cv_name}${local.name_sufix}"
}

resource "azurerm_resource_group" "rg" {
  name     = local.resource_group_name
  location = var.location
}

module "vnet" {
  source               = "./modules/vnet"
  location             = azurerm_resource_group.rg.location
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = var.virtual_network_name
}

module "nsg" {
  source              = "./modules/nsg"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  nsg_apim_name       = "nsg-apim"
  apim_subnet_id      = module.vnet.apim_subnet_id
  nsg_cae_name        = "nsg-cae"
  cae_subnet_id       = module.vnet.cae_subnet_id
  nsg_pe_name         = "nsg-pe"
  pe_subnet_id        = module.vnet.pe_subnet_id
}

module "apim" {
  count                    = var.enable_apim ? 1 : 0
  source                   = "./modules/apim"
  location                 = azurerm_resource_group.rg.location
  resource_group_id        = azurerm_resource_group.rg.id
  resource_group_name      = azurerm_resource_group.rg.name
  apim_name                = local.apim_name
  apim_subnet_id           = module.vnet.apim_subnet_id
  publisher_name           = var.publisher_name
  publisher_email          = var.publisher_email
  appi_resource_id         = module.appi.appi_id
  appi_instrumentation_key = module.appi.appi_key
  openai_service_name      = module.openai.openai_service_name
  openai_service_endpoint  = module.openai.openai_endpoint
  tenant_id                = data.azurerm_subscription.current.tenant_id
  use_private_endpoints    = var.use_private_endpoints

  depends_on = [module.nsg]
}

module "mi" {
  source                = "./modules/mi"
  location              = azurerm_resource_group.rg.location
  resource_group_name   = azurerm_resource_group.rg.name
  managed_identity_name = var.managed_identity_name
}

resource "azurerm_role_assignment" "id_reader" {
  scope                = azurerm_resource_group.rg.id
  role_definition_name = "Reader"
  principal_id         = module.mi.principal_id
}

module "search" {
  source                      = "./modules/search"
  location                    = azurerm_resource_group.rg.location
  resource_group_name         = azurerm_resource_group.rg.name
  search_name                 = local.search_name
  principal_id                = module.mi.principal_id
  allowed_ips                 = local.allowed_ips
  vnet_id                     = module.vnet.virtual_network_id
  private_endpoints_subnet_id = module.vnet.pe_subnet_id
  use_private_endpoints       = var.use_private_endpoints
}

module "log" {
  source              = "./modules/log"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  log_name            = local.log_name
}

module "appi" {
  source              = "./modules/appi"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  appi_name           = local.appi_name
  log_id              = module.log.log_id
}

module "st" {
  source                      = "./modules/st"
  location                    = azurerm_resource_group.rg.location
  resource_group_name         = azurerm_resource_group.rg.name
  storage_account_name        = local.storage_account_name
  principal_id                = module.mi.principal_id
  vnet_id                     = module.vnet.virtual_network_id
  private_endpoints_subnet_id = module.vnet.pe_subnet_id
  use_private_endpoints       = var.use_private_endpoints
  allowed_ips                 = local.allowed_ips
}

module "openai" {
  source                      = "./modules/openai"
  location                    = var.location_azopenai
  resource_group_name         = azurerm_resource_group.rg.name
  azopenai_name               = local.azopenai_name
  principal_id                = module.mi.principal_id
  allowed_ips                 = local.allowed_ips
  vnet_id                     = module.vnet.virtual_network_id
  vnet_location               = azurerm_resource_group.rg.location
  private_endpoints_subnet_id = module.vnet.pe_subnet_id
  use_private_endpoints       = var.use_private_endpoints
}

module "ai_foundry" {
  source                      = "./modules/ai-foundry"
  location                    = azurerm_resource_group.rg.location
  resource_group_name         = azurerm_resource_group.rg.name
  resource_group_id           = azurerm_resource_group.rg.id
  ai_foundry_name             = local.ai_foundry_name
  ai_services_name            = local.ai_services_name
  ai_foundry_project_name     = local.ai_foundry_project_name
  kv_name                     = local.ai_foundry_kv_name
  st_name                     = local.ai_foundry_st_name
  bing_account_name           = local.bing_account_name
  subscription_id             = data.azurerm_subscription.current.subscription_id
  tenant_id                   = data.azurerm_subscription.current.tenant_id
  current_principal_object_id = data.azurerm_client_config.current.object_id
  aihub_principal_id          = module.mi.principal_id
}

module "cog" {
  source                             = "./modules/cog"
  location                           = azurerm_resource_group.rg.location
  resource_group_name                = azurerm_resource_group.rg.name
  resource_group_id                  = azurerm_resource_group.rg.id
  bing_name                          = local.bing_name
  cognitive_services_name            = local.cognitive_services_name
  content_safety_name                = local.content_safety_name
  form_recognizer_name               = local.form_recognizer_name
  speech_name                        = local.speech_name
  vision_name                        = local.vision_name
  vision_location                    = var.location_azopenai
  content_safety_storage_resource_id = module.st.storage_account_id
  content_safety_location            = var.location_content_safety
  allowed_ips                        = local.allowed_ips
  vnet_id                            = module.vnet.virtual_network_id
  private_endpoints_subnet_id        = module.vnet.pe_subnet_id
  use_private_endpoints              = var.use_private_endpoints
}

module "cae" {
  source                 = "./modules/cae"
  location               = azurerm_resource_group.rg.location
  resource_group_name    = azurerm_resource_group.rg.name
  cae_name               = local.cae_name
  cae_subnet_id          = module.vnet.cae_subnet_id
  log_id                 = module.log.log_id
  appi_connection_string = module.appi.appi_connection_string
}

module "ca_chat" {
  source                         = "./modules/ca-chat"
  location                       = azurerm_resource_group.rg.location
  resource_group_id              = azurerm_resource_group.rg.id
  ca_name                        = local.ca_chat_name
  cae_id                         = module.cae.cae_id
  cae_default_domain             = module.cae.default_domain
  managed_identity_id            = module.mi.mi_id
  chat_gpt_deployment            = module.openai.gpt4_deployment_name
  chat_gpt_model                 = module.openai.gpt4_deployment_model_name
  embeddings_deployment          = module.openai.embedding_deployment_name
  embeddings_model               = module.openai.embedding_deployment_name
  storage_account_name           = module.st.storage_account_name
  storage_container_name         = module.st.storage_container_name
  search_service_name            = module.search.search_service_name
  search_index_name              = module.search.search_index_name
  openai_endpoint                = var.enable_apim ? module.apim[0].gateway_url : module.openai.openai_endpoint
  tenant_id                      = data.azurerm_subscription.current.tenant_id
  managed_identity_client_id     = module.mi.client_id
  enable_entra_id_authentication = var.enable_entra_id_authentication
  image_name                     = var.ca_chat_image
}

module "ca_prep_docs" {
  source                     = "./modules/ca-prep-docs"
  location                   = azurerm_resource_group.rg.location
  resource_group_id          = azurerm_resource_group.rg.id
  ca_name                    = local.ca_prep_docs_name
  cae_id                     = module.cae.cae_id
  managed_identity_id        = module.mi.mi_id
  storage_account_name       = module.st.storage_account_name
  storage_account_key        = module.st.key
  search_service_name        = module.search.search_service_name
  tenant_id                  = data.azurerm_subscription.current.tenant_id
  managed_identity_client_id = module.mi.client_id
  openai_service_name        = module.openai.openai_service_name
  resource_group_name        = azurerm_resource_group.rg.name
  subscription_id            = data.azurerm_subscription.current.subscription_id
  image_name                 = var.ca_prep_docs_image
}

module "ca_aihub" {
  source                               = "./modules/ca-aihub"
  location                             = azurerm_resource_group.rg.location
  resource_group_id                    = azurerm_resource_group.rg.id
  ca_name                              = local.ca_aihub_name
  cae_id                               = module.cae.cae_id
  cae_default_domain                   = module.cae.default_domain
  managed_identity_id                  = module.mi.mi_id
  chat_gpt4_deployment                 = module.openai.gpt4_deployment_name
  chat_gpt4_model                      = module.openai.gpt4_deployment_model_name
  chat_gpt4_1_deployment                = module.openai.gpt4_1_deployment_name
  chat_gpt4_1_model                     = module.openai.gpt4_1_deployment_model_name
  chat_gpt4o_deployment                 = module.openai.gpt4o_deployment_name
  chat_gpt4o_model                      = module.openai.gpt4o_deployment_model_name
  embeddings_deployment                 = module.openai.embedding_deployment_name
  embeddings_model                      = module.openai.embedding_deployment_name
  storage_account_name                  = module.st.storage_account_name
  storage_account_key                   = module.st.key
  storage_container_name                = module.st.storage_container_name
  search_service_name                   = module.search.search_service_name
  search_index_name                     = module.search.search_index_name
  openai_endpoint                       = var.enable_apim ? "${module.apim[0].gateway_url}/" : module.openai.openai_endpoint
  chat_fqdn                            = module.ca_chat.fqdn
  pbi_report_link                      = var.pbi_report_link
  content_safety_endpoint              = module.cog.content_safety_endpoint
  content_safety_key                   = module.cog.content_safety_key
  cognitive_service_endpoint           = module.cog.cognitive_service_endpoint
  cognitive_service_key                = module.cog.cognitive_service_key
  speech_key                           = module.cog.speech_key
  vision_endpoint                      = module.cog.vision_endpoint
  vision_key                           = module.cog.vision_key
  storage_connection_string            = module.st.connection_string
  ai_foundry_bing_connection_name      = module.ai_foundry.bing_connection_name
  ai_foundry_deployment_name           = module.ai_foundry.deployment_name
  ai_foundry_project_connection_string = module.ai_foundry.project_connection_string
  tenant_id                            = data.azurerm_subscription.current.tenant_id
  managed_identity_client_id           = module.mi.client_id
  enable_entra_id_authentication       = var.enable_entra_id_authentication
  image_name                           = var.ca_aihub_image
}

module "plugin" {
  count                    = var.enable_openai_plugin_call_transcript ? 1 : 0
  source                   = "./modules/ca-plugin"
  location                 = azurerm_resource_group.rg.location
  resource_group_name      = azurerm_resource_group.rg.name
  resource_group_id        = azurerm_resource_group.rg.id
  func_name                = local.func_name
  image_name               = var.ca_plugin_image
  cae_id                   = module.cae.cae_id
  cae_default_domain       = module.cae.default_domain
  appi_instrumentation_key = module.appi.appi_key
  openai_key               = module.openai.openai_key
  openai_model             = module.openai.gpt4_deployment_name
  openai_endpoint          = module.openai.openai_endpoint
}
