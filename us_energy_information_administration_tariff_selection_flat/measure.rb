# frozen_string_literal: true

# *******************************************************************************
# Original work OpenStudio(R), Copyright (c) 2008-2018, Alliance for Sustainable Energy, LLC.
# Modified work Copyright 2019 Luis Lara
# All rights reserved.
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions are met:
#
# (1) Redistributions of source code must retain the above copyright notice,
# this list of conditions and the following disclaimer.
#
# (2) Redistributions in binary form must reproduce the above copyright notice,
# this list of conditions and the following disclaimer in the documentation
# and/or other materials provided with the distribution.
#
# (3) Neither the name of the copyright holder nor the names of any contributors
# may be used to endorse or promote products derived from this software without
# specific prior written permission from the respective party.
#
# (4) Other than as required in clauses (1) and (2), distributions in any form
# of modifications or other derivative works may not use the "OpenStudio"
# trademark, "OS", "os", or any other confusingly similar designation without
# specific prior written permission from Alliance for Sustainable Energy, LLC.
#
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDER(S) AND ANY CONTRIBUTORS
# "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO,
# THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
# ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER(S), ANY CONTRIBUTORS, THE
# UNITED STATES GOVERNMENT, OR THE UNITED STATES DEPARTMENT OF ENERGY, NOR ANY OF
# THEIR EMPLOYEES, BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL,
# EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT
# OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
# INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT,
# STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY
# OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
# *******************************************************************************

require "#{File.dirname(__FILE__)}/resources/os_lib_helper_methods"
require 'json'

# start the measure
class USEnergyInformationAdministrationTariffSelectionFlat < OpenStudio::Measure::EnergyPlusMeasure
  # human readable name
  def name
    'U.S. Energy Information Administration Tariff Selection-Flat'
  end

  # human readable description
  def description
    'This measure sets flat rates for electricity and gas with information' \
    'from the EIA. Not every year is available for every state. The rates'  \
    'are average values for a specific year, a specific market sector, and' \
    'a specific state. It will throw an error if the specific combination'  \
    'is not available, if so, select a previous year'
  end

  # human readable description of modeling approach
  def modeler_description
    'Read the code, silly.'
  end

  # define the arguments that the user will input
  def arguments(_workspace)
    args = OpenStudio::Measure::OSArgumentVector.new
    file = File.read("#{File.dirname(__FILE__)}/resources/utility_rates.json")
    utility_rates = JSON.parse(file)

    # Add argument for state
    state = OpenStudio::Measure::OSArgument.makeChoiceArgument('state',
                                                               utility_rates.keys,
                                                               true)
    state.setDisplayName('State')
    state.setUnits('$/kWh')
    state.setDefaultValue('Texas')
    args << state

    state = 'Texas'
    markets = utility_rates[state].keys

    # Add argument for market
    market = OpenStudio::Measure::OSArgument.makeChoiceArgument('market',
                                                                markets,
                                                                true)
    market.setDisplayName('Market')
    market.setDefaultValue('Commercial')
    args << market

    market = 'Commercial'
    utility = 'Electricity'
    years = utility_rates[state][market][utility]['Years'].keys

    # Add argument for year
    year = OpenStudio::Measure::OSArgument.makeChoiceArgument('year',
                                                              years,
                                                              true)
    year.setDisplayName('Year')
    year.setDefaultValue('2018')
    args << year

    args
  end

  # define what happens when the measure is run
  def run(workspace, runner, user_arguments)
    super(workspace, runner, user_arguments)

    # Assign the user inputs to variables
    args = OsLib_HelperMethods.createRunVariables(runner,
                                                  workspace,
                                                  user_arguments,
                                                  arguments(workspace))
    return false unless args

    # Parse the JSON file

    file = File.read("#{File.dirname(__FILE__)}/resources/utility_rates.json")
    utility_rates = JSON.parse(file)

    # Report initial condition of model
    st_tar = workspace.getObjectsByType('UtilityCost:Tariff'.to_IddObjectType)
    runner.registerInitialCondition("The model started with \
                                    #{st_tar.size} tariff objects.")

    # Get the rates that match the input, check if the selected rate exists
    elec_rate_s_m = utility_rates[args['state']][args['market']]
    gas_rate_s_m = utility_rates[args['state']][args['market']]

    # Fetch extravaganza
    elec_rate_s_m.fetch('Electricity') { runner.registerError("There are no available electricity rates for #{args['state']} #{args['market']}"); false }
    elec_rate = elec_rate_s_m['Electricity']['Years'].fetch(args['year']) { runner.registerError("There are no available electricity rates for #{args['state']} #{args['market']} for #{args['year']}") }
    gas_rate_s_m.fetch('Gas') { runner.registerError('Your combination of State/Market does not have available gas rates'); false }
    gas_rate = gas_rate_s_m['Gas']['Years'].fetch(args['year']) { runner.registerError("There are no available electricity rates for #{args['state']} #{args['market']} for #{args['year']}") }

    # Divide by 100 to convert to $/unit

    elec_rate /= 100

    # Report

    # elec tariff object
    if elec_rate.positive?
      new_object_string = "
      UtilityCost:Tariff,
        Electricity Tariff,                     !- Name
        ElectricityPurchased:Facility,          !- Output Meter Name
        kWh,                                    !- Conversion Factor Choice
        ,                                       !- Energy Conversion Factor
        ,                                       !- Demand Conversion Factor
        ,                                       !- Time of Use Period Schedule Name
        ,                                       !- Season Schedule Name
        ,                                       !- Month Schedule Name
        Day,                                    !- Demand Window Length
        0.0;                                    !- Monthly Charge or Variable Name
        "
      workspace.addObject(OpenStudio::IdfObject.load(new_object_string).get).get

      # make UtilityCost:Charge:Simple objects for electricity
      new_object_string = "
      UtilityCost:Charge:Simple,
        ElectricityTariffEnergyCharge, !- Name
        Electricity Tariff,                     !- Tariff Name
        totalEnergy,                            !- Source Variable
        Annual,                                 !- Season
        EnergyCharges,                          !- Category Variable Name
        #{elec_rate};          !- Cost per Unit Value or Variable Name
        "
      workspace.addObject(OpenStudio::IdfObject.load(new_object_string).get).get
    end

    # conversion for gas tariff rate
    dollars_per_mcf = gas_rate
    dollars_per_therm = dollars_per_mcf / 10.36

    # gas tariff object
    if gas_rate.positive?
      new_object_string = "
      UtilityCost:Tariff,
        Gas Tariff,                             !- Name
        NaturalGas:Facility,                    !- Output Meter Name
        Therm,                                  !- Conversion Factor Choice
        ,                                       !- Energy Conversion Factor
        ,                                       !- Demand Conversion Factor
        ,                                       !- Time of Use Period Schedule Name
        ,                                       !- Season Schedule Name
        ,                                       !- Month Schedule Name
        Day,                                    !- Demand Window Length
        0.0;                                    !- Monthly Charge or Variable Name
        "
      workspace.addObject(OpenStudio::IdfObject.load(new_object_string).get).get

      # make UtilityCost:Charge:Simple objects for gas
      new_object_string = "
      UtilityCost:Charge:Simple,
        GasTariffEnergyCharge, !- Name
        Gas Tariff,                             !- Tariff Name
        totalEnergy,                            !- Source Variable
        Annual,                                 !- Season
        EnergyCharges,                          !- Category Variable Name
        #{dollars_per_therm};                   !- Cost per Unit Value or Variable Name
        "
      workspace.addObject(OpenStudio::IdfObject.load(new_object_string).get).get
    end

    # report final condition of model
    finishing_tariffs = workspace.getObjectsByType('UtilityCost:Tariff'.to_IddObjectType)
    runner.registerFinalCondition("The model finished with #{finishing_tariffs.size} tariff objects.")

    true
  end
end

# register the measure to be used by the application
USEnergyInformationAdministrationTariffSelectionFlat.new.registerWithApplication
