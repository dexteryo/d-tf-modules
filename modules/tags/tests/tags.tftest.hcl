variables {
  environment = "Integration"
  service     = "Ordering"
  repository  = "example-org/example-infra"
}

run "individual_variables_become_lower_case_mandatory_tags" {
  command = plan

  assert {
    condition     = output.mandatory_tags["Environment"] == "integration" && output.mandatory_tags["Service"] == "ordering" && output.mandatory_tags["Repository"] == "example-org/example-infra" && output.mandatory_tags["ManagedBy"] == "terraform"
    error_message = "Mandatory tags must come from the variables with environment and service in lower case."
  }

  assert {
    condition     = output.all_tags == output.mandatory_tags
    error_message = "Without optional or custom tags all_tags equals the mandatory tags."
  }
}

run "map_form_wins_over_individual_variables" {
  command = plan

  variables {
    mandatory_tags = { Environment = "production" }
  }

  assert {
    condition     = output.environment == "production" && output.service == "ordering"
    error_message = "A key in mandatory_tags must win over the matching variable."
  }
}

run "optional_and_custom_tags_are_merged" {
  command = plan

  variables {
    optional_tags = { Owner = "platform" }
    custom_tags   = { Experiment = "chat" }
  }

  assert {
    condition     = output.all_tags.Owner == "platform" && output.all_tags.Experiment == "chat" && output.all_tags.Service == "ordering"
    error_message = "all_tags must carry mandatory, optional and custom tags."
  }

  assert {
    condition     = output.optional_tags["Owner"] == "platform" && output.custom_tags["Experiment"] == "chat"
    error_message = "The optional and custom outputs must return the inputs."
  }
}

run "missing_mandatory_tag_is_refused" {
  command = plan

  variables {
    repository = ""
  }

  expect_failures = [output.all_tags]
}

run "custom_tag_cannot_reuse_a_mandatory_key" {
  command = plan

  variables {
    custom_tags = { Service = "other" }
  }

  expect_failures = [output.all_tags]
}

run "unknown_optional_key_is_refused" {
  command = plan

  variables {
    optional_tags = { Colour = "blue" }
  }

  expect_failures = [var.optional_tags]
}

run "environment_with_spaces_is_refused" {
  command = plan

  variables {
    environment = "my env"
  }

  expect_failures = [var.environment]
}
