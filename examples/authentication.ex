defmodule Authentication do
  use ExMachine.Statechart

  def definition do
    %State{
      initial: "username",
      substates: %{
        "ask_username" => %State{
          transitions: %{
            "input" => "check_username"
          }
        },
        "check_username" => %State{
          transitions: %{
            "username_ok" => "ask_password",
            "username_ko" => "ask_username"
          }
        },
        "ask_password" => %State{
          transitions: %{
            "input" => "check_password"
          },
        },
        "check_password" => %State{
          transitions: %{
            "password_ok" => "authenticated",
            "password_ko" => "ask_password"
          }
        },
        "authenticated" => %Final{},
        "cancelled" => %Final{}
      },
      transitions: %{
        "cancel" => "cancelled"
      }
    }
  end
end
