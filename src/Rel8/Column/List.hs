{-# language DataKinds #-}
{-# language FlexibleContexts #-}
{-# language LambdaCase #-}
{-# language MultiParamTypeClasses #-}
{-# language RankNTypes #-}
{-# language ScopedTypeVariables #-}
{-# language StandaloneKindSignatures #-}
{-# language TypeApplications #-}
{-# language TypeFamilyDependencies #-}
{-# language UndecidableInstances #-}

module Rel8.Column.List
  ( HList, AHList(..)
  )
where

-- base
import Control.Category ( id )
import Data.Kind ( Type )
import Data.Type.Equality ( (:~:)( Refl ), apply )
import Prelude hiding ( id )

-- rel8
import Rel8.Aggregate ( Aggregate )
import Rel8.Expr ( Expr )
import Rel8.Kind.Context ( SContext(..), Reifiable( contextSing ) )
import Rel8.Schema.Context ( Col )
import Rel8.Schema.Context.Abstract ( exclusivity, virtualOrResult )
import Rel8.Schema.HTable.List ( HListTable )
import qualified Rel8.Schema.Kind as K
import Rel8.Schema.Name ( Name )
import Rel8.Schema.Reify ( Reify, hreify, hunreify )
import Rel8.Schema.Result ( Result, absurd )
import Rel8.Table
  ( Table, Columns, Congruent, Context, fromColumns, toColumns
  , Unreify, reify, unreify, coherence, congruence
  )
import Rel8.Table.List ( ListTable( ListTable ) )
import Rel8.Table.Recontextualize ( Recontextualize )


-- | Nest a list within a 'Rel8able'. @HList f a@ will produce a 'ListTable'
-- @a@ in the 'Expr' context, and a @[a]@ in the 'Result' context.
type HList :: K.Context -> Type -> Type
type family HList context = list | list -> context where
  HList (Reify context) = AHList context
  HList Aggregate = ListTable Aggregate
  HList Expr = ListTable Expr
  HList Name = ListTable Name
  HList Result = []


type AHList :: K.Context -> Type -> Type
newtype AHList context a = AHList (HList context a)


instance (Reifiable context, Table (Reify context) a) =>
  Table (Reify context) (AHList context a)
 where
  type Context (AHList context a) = Reify context
  type Columns (AHList context a) = HListTable (Columns a)
  type Unreify (AHList context a) = HList context (Unreify a)

  fromColumns = sfromColumnsList contextSing
  toColumns = stoColumnsList contextSing

  reify _ = sreifyList contextSing
  unreify _ = sunreifyList contextSing

  coherence = case contextSing @context of
    SAggregate -> coherence @(Reify context) @a
    SExpr -> coherence @(Reify context) @a
    SName -> coherence @(Reify context) @a
    SResult -> \Refl -> absurd
    SReify _ -> \Refl _ -> Refl

  congruence proof@Refl abstract = case contextSing @context of
    SAggregate -> id `apply` congruence @(Reify context) @a proof abstract
    SExpr -> id `apply` congruence @(Reify context) @a proof abstract
    SName -> id `apply` congruence @(Reify context) @a proof abstract
    SResult -> absurd abstract
    SReify _ -> id `apply` congruence @(Reify context) @a proof abstract


instance
  ( Reifiable context, Reifiable context'
  , Recontextualize (Reify context) (Reify context') a a'
  )
  => Recontextualize
    (Reify context)
    (Reify context')
    (AHList context a)
    (AHList context' a')


smapList :: Congruent a b
  => SContext context
  -> (a -> b)
  -> (HListTable (Columns a) (Col (Context a)) -> HListTable (Columns b) (Col (Context b)))
  -> AHList context a
  -> AHList context b
smapList = \case
  SAggregate -> \_ f (AHList (ListTable a)) -> AHList (ListTable (f a))
  SExpr -> \_ f (AHList (ListTable a)) -> AHList (ListTable (f a))
  SResult -> \f _ (AHList as) -> AHList (fmap f as)
  SName -> \_ f (AHList (ListTable a)) -> AHList (ListTable (f a))
  SReify context -> \f g (AHList as) -> AHList (smapList context f g as)


sfromColumnsList :: Table (Reify context) a
  => SContext context
  -> HListTable (Columns a) (Col (Reify context))
  -> AHList context a
sfromColumnsList = \case
  SAggregate -> AHList . ListTable
  SExpr -> AHList . ListTable
  SResult -> AHList . fmap (fromColumns . hreify) . fromColumns . hunreify
  SName -> AHList . ListTable
  SReify context ->
    AHList .
    smapList context (fromColumns . hreify) hreify .
    sfromColumnsList context .
    hunreify


stoColumnsList :: Table (Reify context) a
  => SContext context
  -> AHList context a
  -> HListTable (Columns a) (Col (Reify context))
stoColumnsList = \case
  SAggregate -> \(AHList (ListTable a)) -> a
  SExpr -> \(AHList (ListTable a)) -> a
  SResult ->
    hreify . toColumns . fmap (hunreify . toColumns) . (\(AHList a) -> a)
  SName -> \(AHList (ListTable a)) -> a
  SReify context ->
    hreify .
    stoColumnsList context .
    smapList context (hunreify . toColumns) hunreify .
    (\(AHList a) -> a)


sreifyList :: forall context a. Table (Reify context) a
  => SContext context
  -> HList context (Unreify a)
  -> AHList context a
sreifyList context = case virtualOrResult context of
  Left Refl -> AHList . fmap (reify Refl)
  Right virtual ->
    case coherence @(Reify context) @a Refl abstract of
      Refl -> case congruence @(Reify context) @a Refl abstract of
        Refl ->
          smapList context (reify Refl) hreify .
          AHList
    where
      abstract = exclusivity virtual


sunreifyList :: forall context a. Table (Reify context) a
  => SContext context
  -> AHList context a
  -> HList context (Unreify a)
sunreifyList context = case virtualOrResult context of
  Left Refl -> fmap (unreify Refl) . (\(AHList a) -> a)
  Right virtual ->
    case coherence @(Reify context) @a Refl abstract of
      Refl -> case congruence @(Reify context) @a Refl abstract of
        Refl ->
          (\(AHList a) -> a) .
          smapList context (unreify Refl) hunreify
    where
      abstract = exclusivity virtual
